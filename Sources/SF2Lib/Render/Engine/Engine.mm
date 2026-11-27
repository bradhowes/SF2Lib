// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include <cstdint>
#include <cstring>
#include <vector>

#include "DSPHeaders/Types.hpp"
#include "SF2Util/Base64.hpp"
#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/LoadPresetSysExPayload.hpp"
#include "SF2File/IO/File.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

Engine::Engine()
  : super(Log::create("Engine")),
    sampleRate_{0},
    parameters_{},
    oldestVoiceIndices_{},
    renderSignpost_{os_signpost_id_generate(log_)},
    noteOnSignpost_{os_signpost_id_generate(log_)},
    noteOffSignpost_{os_signpost_id_generate(log_)},
    startVoiceSignpost_{os_signpost_id_generate(log_)},
    stopVoiceSignpost_{os_signpost_id_generate(log_)},
    workQueue_{dispatch_queue_create("SF2Lib::Engine", DISPATCH_QUEUE_SERIAL)},
    activeVoiceCountQueue_{dispatch_queue_create("SF2Lib::Engine.activeVoiceCount", DISPATCH_QUEUE_SERIAL)}
{
  makeTree();
}

void
Engine::setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender) noexcept
{
  super::setRenderingFormat(busCount, format, maxFramesToRender);
  initialize(Float(format.sampleRate));
}

bool
Engine::hasActivePreset() const noexcept
{
  auto ptr = presetsState();
  return ptr ? ptr->hasActivePreset() : false;
}

std::string
Engine::activePresetName() const
{
  auto ptr = presetsState();
  return ptr && ptr->hasActivePreset() ? ptr->activePreset().configuration().name() : "";
}

int
Engine::activeProgramIndex() const noexcept
{
  auto ptr = presetsState();
  return ptr && ptr->hasActivePreset() ? ptr->activePreset().configuration().program() : -1;
}

int
Engine::activeBankIndex() const noexcept
{
  auto ptr = presetsState();
  return ptr && ptr->hasActivePreset() ? ptr->activePreset().configuration().bank() : -1;
}

int
Engine::activePresetIndex() const noexcept
{
  // NOTE: this value is only used/reported in the AUParameterTree -- not to be used in place of `activePreset_` value which is the
  // only real preset index value to be used in the engine.
  auto ptr = presetsState();
  return ptr ? int(ptr->activePresetIndex()) : -1;
}

Engine::~Engine()
{
  // The publishing timer uses this instance.
  stopPublishingActiveVoiceCount();

  // Let queued loads finish: they use this instance.
  dispatch_sync(workQueue_, ^{ });
  std::lock_guard<std::mutex> lock(retiredMutex_);
  reclaimRetiredPresetsStates_WQ(true);
  delete presetsState_.exchange(nullptr);
}

void
Engine::usePresetWithIndex_WQ(size_t index)
{
  assert(presetChangesPending_.load() > 0);

  // NOTE: this changes the samples of the published state. That is only safe because the render thread has stopped
  // all voices and `presetChangesPending_` blocks new ones until `finishPresetChange_WQ`.
  auto ptr = presetsState();
  if (ptr) {
    ptr->changeActivePreset(index);
  }
  finishPresetChange_WQ();
}

void
Engine::usePresetRequest_WQ(void* context) noexcept
{
  auto self = static_cast<Engine*>(context);
  auto index = self->requestedPresetIndex_.load(std::memory_order_acquire);
  auto ptr = self->presetsState();
  // A burst of program changes queues one request each, but they all read the latest index. Skip the repeats.
  if (ptr && ptr->hasActivePreset() && ptr->activePresetIndex() == index) {
    self->finishPresetChange_WQ();
  } else {
    self->usePresetWithIndex_WQ(index);
  }
}

void
Engine::finishPresetChange_WQ() noexcept
{
  parameters_.reset();
  bumpLastLoadFinished_WQ();

  auto ptr = presetsState();
  auto preset = ptr ? ptr->activePresetOrNull() : nullptr;
  os_log_debug(log_, "finishPresetChange_WQ - %{public}s", preset ? preset->configuration().name().c_str() : "???");

  // Last, so that the render thread does not start voices before the change is complete.
  --presetChangesPending_;
}

void
Engine::installPresetsState_WQ(PresetsState* state)
{
  auto old = presetsState_.exchange(state, std::memory_order_acq_rel);
  std::lock_guard<std::mutex> lock(retiredMutex_);
  if (old != nullptr) retired_.push_back(old);
  reclaimRetiredPresetsStates_WQ(false);
}

void
Engine::reclaimRetiredPresetsStates_WQ(bool all) noexcept
{
  // A retired state can be freed once the render thread has switched to a newer generation: at that point it has
  // stopped every voice that could still reference the retired state's samples, and it no longer holds a pointer to it.
  auto acknowledged = renderGeneration_.load(std::memory_order_acquire);
  std::erase_if(retired_, [all, acknowledged](PresetsState* state) {
    if (!all && state->generation() >= acknowledged) return false;
    delete state;
    return true;
  });
}

PresetsState*
Engine::syncPresetsState_RT() noexcept
{
  auto state = presetsState_.load(std::memory_order_acquire);
  auto generation = state != nullptr ? state->generation() : 0;
  if (generation != renderGeneration_.load(std::memory_order_relaxed)) {
    // Voices from the previous state reference its samples, which may be freed once we acknowledge the new state.
    allOff_RT();
    renderGeneration_.store(generation, std::memory_order_release);
  }
  return state;
}

void
Engine::allOff_RT() noexcept
{
  // !!! NOTE: must only be done on the render thread.
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    pos = stopVoice_RT(*pos);
  }
}

void
Engine::noteOn_RT(int key, int velocity) noexcept
{
  os_signpost_interval_begin(log_, noteOnSignpost_, "noteOn_RT");

  if (presetChangesPending_.load() == 0) {
    auto ptr = syncPresetsState_RT();
    auto preset = ptr != nullptr ? ptr->activePresetOrNull() : nullptr;
    if (preset != nullptr) {

      if (channelState_.pedalState().softPedalActive) {
        velocity /= 2;
      }

      auto configs = preset->find(key, velocity);

      // Stop any existing voice with the same exclusiveClass value.
      for (const Config& config : configs) {
        auto exclusiveClass{config.exclusiveClass()};
        if (exclusiveClass > 0) {
          stopAllExclusiveVoices_RT(exclusiveClass);
        }
        if (oneVoicePerKeyModeEnabled_) {
          stopSameKeyVoices_RT(config.eventKey());
        }
      }

      std::array<size_t, Preset::maxConfigsPerNote> voiceIndices;
      for (size_t index = 0; index < configs.size(); ++index) {
        voiceIndices[index] = startVoice_RT(configs[index]);
      }
      linkStereoPairs_RT(configs, voiceIndices);
    }
  }

  os_signpost_interval_end(log_, noteOnSignpost_, "noteOn_RT");
}

void
Engine::noteOff_RT(int key) noexcept
{
  os_signpost_interval_begin(log_, noteOffSignpost_, "noteOff_RT");
  visitActiveVoice_RT([=](Voice& voice, const Voice::ReleaseKeyState& releaseKeyState) {
    if (voice.initiatingKey() == key) {
      voice.releaseKey(releaseKeyState);
    }
  });
  os_signpost_interval_end(log_, noteOffSignpost_, "noteOff_RT");
}

void
Engine::applySostenutoPedal_RT() noexcept
{
  visitActiveVoice_RT([](Voice& voice, const Voice::ReleaseKeyState&) {
    if (voice.isKeyDown()) voice.useSostenuto();
  });
}

void
Engine::releaseKeys_RT() noexcept
{
  visitActiveVoice_RT([](Voice& voice, const Voice::ReleaseKeyState& releaseKeyState) {
    voice.releaseKey(releaseKeyState);
  }, Voice::ReleaseKeyState{0u, MIDI::ChannelState::PedalState()});
}

void
Engine::applyPedals_RT() noexcept
{
  visitActiveVoice_RT([](Voice& voice, const Voice::ReleaseKeyState& releaseKeyState) {
    voice.pedalReleased(releaseKeyState.pedalState);
  });
}

void
Engine::renderInto(Mixer mixer, AUAudioFrameCount frameCount) noexcept
{
  syncPresetsState_RT();
  if (activeVoiceCount() == 0) return;

  auto timeBudget = timeBudgetNanoseconds(frameCount);
  auto budgeted = renderingTimeBudgetScaling_ > 0.0;
  auto entryTime = budgeted ? clock_() : 0;
  if (budgeted) shedVoicesOverBudget_RT(frameCount, timeBudget);

  // Iterate over the active voices -- the voices are ordered from newest to oldest. If we run out of time, the oldest
  // ones are faded out over a few frames and stopped. (Stopping a sounding voice outright would click.)
  //
  // The two voices of a stereo pair (SF2.01 7.10) are rendered together, in lockstep, when the loop reaches either of
  // them: the right-sample voice supplies the pitch for both. `renderSlice_` marks voices already rendered here.
  ++renderSlice_;
  uint64_t voiceFrames = 0;
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    auto voiceIndex = *pos;

    auto& voice{voices_[voiceIndex]};
    if (voice.renderedSlice() != renderSlice_) {
      auto partnerIndex = voice.partner();
      auto partner = (partnerIndex != Voice::noPartner && voices_[partnerIndex].isActive()) ? &voices_[partnerIndex]
                                                                                             : nullptr;
      auto& leader = (partner != nullptr && !voice.isPitchLeader()) ? *partner : voice;
      auto follower = partner == nullptr ? nullptr : (&leader == &voice ? partner : &voice);
      auto renderedVoices = follower != nullptr ? 2 : 1;

      if (voice.isActive() || follower != nullptr) {
        if (!budgeted || clock_() - entryTime < timeBudget) {
          if (follower != nullptr) {
            leader.renderLinkedInto(*follower, mixer, frameCount);
          } else {
            voice.renderInto(mixer, frameCount);
          }
          voiceFrames += frameCount * renderedVoices;
        } else {
          auto fadeFrames = std::min(frameCount, budgetFadeOutFrames);
          if (follower != nullptr) {
            leader.renderLinkedFadeOut(*follower, mixer, fadeFrames);
          } else {
            voice.renderFadeOut(mixer, fadeFrames);
          }
          voiceFrames += fadeFrames * renderedVoices;
        }
      } else {
        os_log_error(log_, "renderInto - encountered active voice that is not active - %lu", voiceIndex);
      }

      voice.markRendered(renderSlice_);
      if (follower != nullptr) {
        // `partnerIndex` is the other voice of the pair (use it, not `Voice::voiceIndex()`, which is only set for
        // initialised voices).
        auto& other = voices_[partnerIndex];
        other.markRendered(renderSlice_);
        // The other voice sits later in the list (had it come first, it would have rendered this pair already).
        // Release it now if it has finished; the loop only advances past the current position, which is unaffected.
        if (other.isDone()) stopVoice_RT(partnerIndex);
      }
    }

    if (voice.isDone()) {
      pos = stopVoice_RT(voiceIndex);
    } else {
      ++pos;
    }
  }

  // Update the running average of the cost of one voice for one frame, used by `shedVoicesOverBudget_RT`.
  if (budgeted && voiceFrames > 0) {
    auto measured = double(clock_() - entryTime) / double(voiceFrames);
    averageVoiceFrameNanoseconds_ = averageVoiceFrameNanoseconds_ == 0.0
    ? measured
    : averageVoiceFrameNanoseconds_ + voiceCostSmoothing * (measured - averageVoiceFrameNanoseconds_);
  }
}

void
Engine::shedVoicesOverBudget_RT(AUAudioFrameCount frameCount, uint64_t timeBudget) noexcept
{
  auto voiceCost = averageVoiceFrameNanoseconds_ * double(frameCount);
  if (voiceCost <= 0.0) return;
  auto affordable = std::max<size_t>(1, size_t(double(timeBudget) / voiceCost));
  if (activeVoiceCount() <= affordable) return;

  // Newest to oldest: keep the first `affordable` voices, fast-release the rest.
  size_t counted = 0;
  for (auto voiceIndex : oldestVoiceIndices_) {
    auto& voice{voices_[voiceIndex]};
    if (!voice.isActive()) continue;
    if (++counted > affordable && !voice.isFastReleasing()) {
      voice.fastRelease();
      // Keep a stereo pair together: shed both halves (SF2.01 7.10, "played entirely synchronously").
      auto partner = voice.partner();
      if (partner != Voice::noPartner && voices_[partner].isActive()) voices_[partner].fastRelease();
    }
  }
}

AUAudioFrameCount
Engine::doParameterEvent(const AUParameterEvent& event, AUAudioFrameCount duration) noexcept {
  // NOTE: this is running in the real-time render thread.
  auto rawIndex = event.parameterAddress;
  auto value = event.value;
  if (rawIndex < 0) return 0;
  if (rawIndex < DSPHeaders::valueOf(Entity::Generator::Index::numValues)) {
    auto index = Entity::Generator::Index(rawIndex);
    parameters_.setLiveValue(index, value);
    notifyParameterChanged_RT(index);
    return duration;
  } else if (rawIndex >= DSPHeaders::valueOf(ParameterAddress::firstParameterAddress) &&
             rawIndex < DSPHeaders::valueOf(ParameterAddress::lastParameterAddressPlusOne)) {
    auto address = ParameterAddress(rawIndex);
    switch (address) {
      case ParameterAddress::portamentoModeEnabled:
        setPortamentoModeEnabled(DSPHeaders::toBool(value));
        break;
      case ParameterAddress::portamentoRate:
        setPortamentoRate(size_t(value));
        break;
      case ParameterAddress::oneVoicePerKeyModeEnabled:
        setOneVoicePerKeyModeEnabled(DSPHeaders::toBool(value));
        break;
      case ParameterAddress::polyphonicModeEnabled:
        setPhonicMode(DSPHeaders::toBool(value) ? Engine::PhonicMode::poly : Engine::PhonicMode::mono);
        break;
      case ParameterAddress::retriggerModeEnabled:
        setRetriggerModeEnabled(DSPHeaders::toBool(value));
        break;
      default:
        break;
    }
  }
  return 0;
}

void
Engine::doRenderingStateChanged(bool state) noexcept
{
  if (!state) {
    allOff_RT();

    // Post a sentinal item to work queue so we know all pending items are done. Since the render thread is no longer operating at
    // this point, we know there will be no more added and from now on it is safe for the Engine to be destroyed.
    dispatch_sync(workQueue_, ^{ });

    auto value = presetChangesPending_.load();
    if (value != 0) {
      os_log_error(log_, "doRenderingStateChanged - detected non-zero presetChangesPending at stop of render loop - %d", value);
      presetChangesPending_.store(0);
    }

    // The render thread is not running, so no retired state is in use.
    std::lock_guard<std::mutex> lock(retiredMutex_);
    reclaimRetiredPresetsStates_WQ(true);
  }

  if (state) {
    renderSlice_ = 0;
    startPublishingActiveVoiceCount();
  } else {
    stopPublishingActiveVoiceCount();
  }

  // OK to do here since technically we are not yet rendering.
  [[parameterTree_ parameterWithAddress: DSPHeaders::valueOf(ParameterAddress::isRendering)] setValue: DSPHeaders::fromBool(state)];
}

void
Engine::publishActiveVoiceCount() noexcept
{
  auto value = activeVoiceCountShared_.load(std::memory_order_relaxed);
  if (value == activeVoiceCountPublished_) return;
  auto parameter = [parameterTree_ parameterWithAddress: DSPHeaders::valueOf(ParameterAddress::activeVoiceCount)];
  if (parameter == nil) return;
  activeVoiceCountPublished_ = value;
  [parameter setValue: AUValue(value)];
}

void
Engine::startPublishingActiveVoiceCount() noexcept
{
  if (activeVoiceCountTimer_ == nullptr) {
    activeVoiceCountTimer_ = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, activeVoiceCountQueue_);
    dispatch_source_set_timer(activeVoiceCountTimer_, dispatch_time(DISPATCH_TIME_NOW, 0),
                              uint64_t(activeVoiceCountPublishIntervalNanoseconds), 10 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(activeVoiceCountTimer_, ^{ publishActiveVoiceCount(); });
    dispatch_resume(activeVoiceCountTimer_);
  }
}

void
Engine::stopPublishingActiveVoiceCount() noexcept
{
  if (activeVoiceCountTimer_ != nullptr) {
    dispatch_source_cancel(activeVoiceCountTimer_);
    activeVoiceCountTimer_ = nullptr;
  }
  // Wait for any handler that is running, and publish the final count (0 once rendering has stopped). No handler runs
  // after this, so the instance can then be destroyed.
  dispatch_sync(activeVoiceCountQueue_, ^{ publishActiveVoiceCount(); });
}

void
Engine::doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept
{
  os_log_debug(log_, "doMIDIEvent BEGIN - %d", midiEvent.length);

  if (midiEvent.length < 1) {
    os_log_debug(log_, "doMIDIEvent BEGIN - no bytes");
    return;
  }

  if (midiEvent.data[0] < 0x80) {
    os_log_debug(log_, "doMIDIEvent END - invalid first byte %d", midiEvent.data[0]);
    return;
  }

  auto event = MIDI::CoreEvent(midiEvent.data[0] < DSPHeaders::valueOf(MIDI::CoreEvent::systemExclusive)
                               ? (midiEvent.data[0] & DSPHeaders::valueOf(MIDI::CoreEvent::systemExclusive))
                               : midiEvent.data[0]);
  switch (event) {
    case MIDI::CoreEvent::noteOff:
      os_log_debug(log_, "doMIDIEvent noteOff");
      if (midiEvent.length > 1) {
        noteOff_RT(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::noteOn:
      if (midiEvent.length > 1) {
        auto velocity = midiEvent.length == 3 ? midiEvent.data[2] : 0;
        if (velocity > 0) {
          os_log_debug(log_, "doMIDIEvent noteOn");
          noteOn_RT(midiEvent.data[1], velocity);
        } else {
          os_log_debug(log_, "doMIDIEvent noteOff (zero velocity noteOn");
          noteOff_RT(midiEvent.data[1]);
        }
      }
      break;

    case MIDI::CoreEvent::keyPressure:
      os_log_debug(log_, "doMIDIEvent keyPressure");
      if (midiEvent.length == 3) {
        channelState_.setNotePressure(midiEvent.data[1], midiEvent.data[2]);
        notifyActiveVoicesChannelStateChanged_RT();
      }
      break;

    case MIDI::CoreEvent::controlChange:
      os_log_debug(log_, "doMIDIEvent controlChange");
      if (midiEvent.length == 3) {
        auto what = MIDI::ControlChange(midiEvent.data[1]);
        auto data = midiEvent.data[2];
        if (midiEvent.data[1] < 120) {
          processControlChange_RT(what, data);
        } else {
          processChannelMessage_RT(what, data);
        }
      }
      break;

    case MIDI::CoreEvent::programChange:
      os_log_debug(log_, "doMIDIEvent programChange");
      if (midiEvent.length >= 2) {
        changeProgram_RT(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::channelPressure:
      os_log_debug(log_, "doMIDIEvent channelPressure");
      if (midiEvent.length >= 2) {
        channelState_.setChannelPressure(midiEvent.data[1]);
        notifyActiveVoicesChannelStateChanged_RT();
      }
      break;

    case MIDI::CoreEvent::pitchBend:
      os_log_debug(log_, "doMIDIEvent pitchBend");
      if (midiEvent.length == 3) {
        int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
        channelState_.setPitchWheelValue(bend);
        notifyActiveVoicesChannelStateChanged_RT();
      }
      break;

    case MIDI::CoreEvent::systemExclusive:
      os_log_debug(log_, "doMIDIEvent systemExclusive");
      if (midiEvent.length >= 3 &&
          midiEvent.data[1] == LoadPresetSysExPayload::manufacturerValue &&
          midiEvent.data[midiEvent.length - 1] == DSPHeaders::valueOf(MIDI::CoreEvent::EOX) &&
          (midiEvent.data[2] == LoadPresetSysExPayload::modelPathPayload ||
           midiEvent.data[2] == LoadPresetSysExPayload::modelBookmarkPayload)) {
        queueSysExRequest_RT(midiEvent);
      } else {
        os_log_debug(log_, "doMIDIEvent - systemExclusive ignored");
      }
      break;

    case MIDI::CoreEvent::reset:
      os_log_debug(log_, "doMIDIEvent reset");
      reset_RT();
      break;

    default:
      os_log_debug(log_, "doMIDIEvent - ignored %hhX", midiEvent.data[0]);
      break;
  }

  os_log_debug(log_, "doMIDIEvent END");
}

void
Engine::processChannelMessage_RT(MIDI::ControlChange channelMessage, uint8_t value) noexcept
{
  os_log_debug(log_, "processChannelMessage_RT - %d value: %d", channelMessage, value);
  switch (channelMessage) {
    case MIDI::ControlChange::allSoundOff:
      allOff_RT();
      break;

    case MIDI::ControlChange::resetAllControllers:
      resetAllControllers_RT();
      break;

//    case MIDI::ControlChange::localControl:
//      break;

    case MIDI::ControlChange::allNotesOff:
      releaseKeys_RT();
      break;

    case MIDI::ControlChange::omniOff:
      allOff_RT();
      break;

    case MIDI::ControlChange::omniOn:
      allOff_RT();
      break;

    case MIDI::ControlChange::monoOn:
      allOff_RT();
      setPhonicMode(PhonicMode::mono);
      break;

    case MIDI::ControlChange::polyOn:
      allOff_RT();
      setPhonicMode(PhonicMode::poly);
      break;

    default: break;
  }
}

void
Engine::processControlChange_RT(MIDI::ControlChange cc, uint8_t value) noexcept
{
  auto previousPedalState = channelState_.pedalState();

  // Delegate the processing of the CC values. If a value was actually changed, then notify the active voices so that
  // they can update their generators that rely on CC values.
  if (channelState_.setContinuousControllerValue(cc, value)) {
    notifyActiveVoicesChannelStateChanged_RT();
  }

  // Now check if there is a pedal change that can affect note off responses in a voice.
  auto currentPedalState = channelState_.pedalState();
  auto doRelease = false;

  if (!previousPedalState.sostenutoPedalActive) {
    if (currentPedalState.sostenutoPedalActive) {
      applySostenutoPedal_RT();
    }
  } else {
    doRelease = !currentPedalState.sostenutoPedalActive;
  }

  if (previousPedalState.sustainPedalActive && !currentPedalState.sustainPedalActive) {
    doRelease = true;
  }

  if (doRelease) {
    applyPedals_RT();
  }
}

void
Engine::notifyParameterChanged_RT(Entity::Generator::Index index) noexcept
{
  visitActiveVoice_RT([&](Voice& voice, const Voice::ReleaseKeyState&) {
    parameters_.applyOneGenerator(voice.state(), index);
  });
}

void
Engine::notifyActiveVoicesChannelStateChanged_RT() noexcept
{
  visitActiveVoice_RT([&](Voice& voice, const Voice::ReleaseKeyState&) { voice.channelStateChanged(channelState_); });
}

bool
Engine::queueSysExRequest_RT(const AUMIDIEvent& midiEvent) noexcept {
  if (midiEvent.length < LoadPresetSysExPayload::minPayloadSize || midiEvent.length > SysExRequest::capacity) {
    os_log_error(log_, "queueSysExRequest_RT - invalid payload length %d", midiEvent.length);
    return false;
  }

  for (auto& request : sysExRequests_) {
    if (request.busy.exchange(true, std::memory_order_acquire)) continue;
    request.engine = this;
    request.length = midiEvent.length;
    std::memcpy(request.bytes.data(), midiEvent.data, midiEvent.length);

    // Stop all existing voices and block future ones from starting until the load is done.
    allOff_RT();
    ++presetChangesPending_;

    // Parsing, Base64 decoding, NSData and the load itself all happen on the work queue. `dispatch_async_f` takes a
    // plain function, so no block is copied on the render thread.
    dispatch_async_f(workQueue_, &request, &Engine::processSysExRequest_WQ);
    return true;
  }

  os_log_error(log_, "queueSysExRequest_RT - all request slots busy; dropping request");
  return false;
}

void
Engine::processSysExRequest_WQ(void* context) noexcept {
  auto request = static_cast<SysExRequest*>(context);
  request->engine->processSysExRequest_WQ(request->bytes.data(), request->length);
  request->busy.store(false, std::memory_order_release);
}

void
Engine::processSysExRequest_WQ(const uint8_t* msg, size_t length) {

  // From doMIDIEvent we have confirmed that:
  // - length >= 3
  // - msg[0] == MIDI::CoreEvent::systemExclusive
  // - msg[1] == LoadPresetSysExPayload::manufacturerValue
  // - msg[2] == LoadPresetSysExPayload::modelPathPayload OR LoadPresetSysExPayload::modelBookmarkPayload
  // - msg[length - 1] == MIDI::CoreEvent::EOX
  //
  // The Base64-encoded payload consists of bytes in msg[3]...msg[length - 2].
  //
  // NOTE: this routine does not run on the audio render thread, so we are safe to allocate memory here, for the decoding of the
  // SysEx payload and the Generator override vector (TODO).
  //
  auto ptr = reinterpret_cast<const char*>(msg + 3);
  auto decoded = SF2::Utils::Base64::decode({ptr, length - 4});
  if (!decoded.has_value()) {
    os_log_error(log_, "processSysExRequest_WQ - failed to decode Base64 payload");
    --presetChangesPending_;
    return;
  }

  auto decodedBytes = decoded.value();
  auto available = decodedBytes.size();

  if (available < sizeof(LoadPresetSysExPayload::Fixed)) {
    os_log_error(log_, "processSysExRequest_WQ - decodedBytes too small for LoadPresetSysExPayload::Payload");
    --presetChangesPending_;
    return;
  }

  const LoadPresetSysExPayload::Fixed* payload = reinterpret_cast<const LoadPresetSysExPayload::Fixed*>(decodedBytes.data());
  auto presetIndex = payload->presetIndex;
  auto overrideCount = payload->overrideCount;
  available -= sizeof(LoadPresetSysExPayload::Fixed);

  if (available < overrideCount * sizeof(MIDI::GeneratorOverride)) {
    os_log_error(log_, "processSysExRequest_WQ - decodedBytes too small for LoadPresetSysExPayload.overrideCount");
    --presetChangesPending_;
    return;
  }

  const MIDI::GeneratorOverride* pos = reinterpret_cast<const MIDI::GeneratorOverride*>(payload + 1);
  MIDI::GeneratorOverrideVector overrides;
  while (overrideCount-- > 0) {
    overrides.push_back(*pos++);
    available -= sizeof(SF2::MIDI::GeneratorOverride);
  }

  auto pathStart = reinterpret_cast<const char*>(pos);

  switch (msg[2]) {
    case LoadPresetSysExPayload::modelPathPayload: {
      auto path = available == 0 ? std::string("") : std::string(pathStart, available);
        beginLoadFileAndPreset_WQ(path, payload->presetIndex);
        break;
    }

    case LoadPresetSysExPayload::modelBookmarkPayload: {
      NSData* bookmark = [NSData dataWithBytes:pathStart length:available];
      if (bookmark == nil) {
        os_log_error(log_, "processSysExRequest_WQ - invalid Base64 bookmark");
        --presetChangesPending_;
        return;
      }
      beginLoadBookmarkAndPreset_WQ(bookmark, payload->presetIndex);
      break;
    }

      // Seems as if the check in doMIDIEvent is no longer accurate.
    default:
      os_log_error(log_, "processSysExRequest_WQ - unknown SysEx model %d", msg[2]);
      --presetChangesPending_;
      break;
  }
}

SF2::IO::File::LoadResponse
Engine::loadFileAndPreset(std::string path, size_t presetIndex) {
  ++presetChangesPending_;
  return beginLoadFileAndPreset_WQ(path, presetIndex);
}

SF2::IO::File::LoadResponse
Engine::loadFileAndPreset(int fd, size_t presetIndex) {
  ++presetChangesPending_;
  return concludeLoad_WQ(fd, presetIndex);
}

SF2::IO::File::LoadResponse
Engine::beginLoadFileAndPreset_WQ(std::string path, size_t presetIndex) {
  os_log_debug(log_, "beginLoadFileAndPreset_WQ BEGIN");
  if (!path.empty()) {
    return concludeLoad_WQ(path, presetIndex);
  }
  usePresetWithIndex_WQ(presetIndex);
  auto ptr = presetsState();
  auto response = ptr != nullptr ? ptr->loadResponse() : SF2::IO::File::LoadResponse::none;
  os_log_debug(log_, "beginLoadFileAndPreset_WQ END - %d", response);
  return response;
}

SF2::IO::File::LoadResponse
Engine::concludeLoad_WQ(const std::string& path, size_t index)
{
  os_log_debug(log_, "concludeLoad_WQ - path: '%{public}s' index: %lu", path.c_str(), index);
  assert(presetChangesPending_.load() > 0);

  // Build the new state and load its active preset's samples before the render thread can see it. The old state is
  // retired and freed once the render thread has switched away from it.
  auto state = new PresetsState(path, index, nextGeneration_++);
  state->changeActivePreset(index);
  auto response = state->loadResponse();
  installPresetsState_WQ(state);
  finishPresetChange_WQ();
  os_log_debug(log_, "concludeLoad_WQ END - %d", response);
  return response;
}

SF2::IO::File::LoadResponse
Engine::loadBookmarkAndPreset(NSData *bookmark, size_t presetIndex) {
  ++presetChangesPending_;
  return beginLoadBookmarkAndPreset_WQ(bookmark, presetIndex);
}

SF2::IO::File::LoadResponse
Engine::beginLoadBookmarkAndPreset_WQ(NSData* bookmark, size_t presetIndex) {
  os_log_debug(log_, "loadBookmarkAndPreset BEGIN");

  NSError* error = nil;
  BOOL isStale = NO;
  NSURL* resolved = [NSURL URLByResolvingBookmarkData:bookmark
                                              options:0
                                        relativeToURL:nil
                                  bookmarkDataIsStale:&isStale
                                                error:&error];

  // Every exit that does not load must undo the caller's `++presetChangesPending_`, or note-on stays blocked.
  if (error != nil) {
    os_log_error(log_, "loadBookmarkAndPreset END - error from resolving bookmark data - %{public}@", error);
    --presetChangesPending_;
    return SF2::IO::File::LoadResponse::notFound;
  } else if (resolved == nil) {
    os_log_error(log_, "loadBookmarkAndPreset END - failed to resolve bookmark data (no error)");
    --presetChangesPending_;
    return SF2::IO::File::LoadResponse::notFound;
  } else {
    os_log_error(log_, "loadBookmarkAndPreset - resolved bookmark: %{public}@", resolved);
  }

  BOOL didStart = NO;
  if ([resolved respondsToSelector:@selector(startAccessingSecurityScopedResource)]) {
    didStart = [resolved startAccessingSecurityScopedResource];
  }

  error = nil;

  __block auto response = SF2::IO::File::LoadResponse::notFound;
  NSFileCoordinator* coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
  [coordinator coordinateReadingItemAtURL:resolved
                                  options:NSFileCoordinatorReadingWithoutChanges
                                    error:&error
                               byAccessor:^(NSURL* url) {
    NSError* err2 = nil;
    NSFileHandle* fileHandle = [NSFileHandle fileHandleForReadingFromURL:url error:&err2];
    if (err2 != nil) {
      os_log_error(log_, "loadBookmarkAndPreset - failed to open file: %{public}@", err2);
      return;
    }

    os_log_debug(log_, "loading from resolved url - file descriptor: %d", fileHandle.fileDescriptor);

    // `File::load(int)` duplicates the descriptor, so the file stays readable after `fileHandle` is released (closing
    // its descriptor) at the end of this block and after security-scoped access stops below. Later program changes
    // load their samples through the duplicate.
    response = concludeLoad_WQ(fileHandle.fileDescriptor, presetIndex);
  }];

  if (didStart) {
    [resolved stopAccessingSecurityScopedResource];
  }

  // The accessor block does not run if coordination fails, and returns early if the file cannot be opened.
  if (response == SF2::IO::File::LoadResponse::notFound) --presetChangesPending_;
  os_log_debug(log_, "loadBookmarkAndPreset END - %d", response);
  return response;
}

SF2::IO::File::LoadResponse
Engine::concludeLoad_WQ(int fd, size_t index)
{
  os_log_debug(log_, "concludeLoad - fd: %d index: %lu", fd, index);
  assert(presetChangesPending_.load() > 0);

  // See `concludeLoad_WQ(path, index)`.
  auto state = new PresetsState(fd, index, nextGeneration_++);
  state->changeActivePreset(index);
  auto response = state->loadResponse();
  installPresetsState_WQ(state);
  finishPresetChange_WQ();
  os_log_debug(log_, "concludeLoad END - %d", response);
  return response;
}

std::vector<uint8_t>
Engine::createLoadFileUsePresetPayload(const std::string& filePath, size_t presetIndex,
                                       const MIDI::GeneratorOverrideVector& overrides)
{
  return LoadPresetSysExPayload::make(overrides, filePath, presetIndex);
}

std::vector<uint8_t>
Engine::createLoadBookmarkUsePresetPayload(const NSData* bookmark, size_t presetIndex,
                                           const std::vector<SF2::MIDI::GeneratorOverride>& overrides)
{
  return LoadPresetSysExPayload::make(overrides, bookmark, presetIndex);
}

std::array<uint8_t, 1>
Engine::createResetCommandPayload() noexcept
{
  return std::array<uint8_t, 1>{
    DSPHeaders::valueOf(MIDI::CoreEvent::reset)
  };
}

std::array<uint8_t, 3>
Engine::createChannelMessagePayload(MIDI::ControlChange channelMessage, uint8_t value) noexcept
{
  return std::array<uint8_t, 3>{
    DSPHeaders::valueOf(MIDI::CoreEvent::controlChange),
    DSPHeaders::valueOf(channelMessage),
    value
  };
}

std::array<uint8_t, 9>
Engine::createUseBankProgramPayload(uint16_t bank, uint8_t program) noexcept
{
  assert(bank < 128 * 128 && program < 128);
  auto bankMSB = uint8_t(bank / 128u);
  auto bankLSB = uint8_t(bank - bankMSB * 128u);
  return std::array<uint8_t, 9>{
    DSPHeaders::valueOf(MIDI::CoreEvent::controlChange),
    DSPHeaders::valueOf(MIDI::ControlChange::bankSelectMSB),
    bankMSB,
    DSPHeaders::valueOf(MIDI::CoreEvent::controlChange),
    DSPHeaders::valueOf(MIDI::ControlChange::bankSelectLSB),
    bankLSB,
    DSPHeaders::valueOf(MIDI::CoreEvent::programChange),
    program,
    0
  };
}

void
Engine::changeProgram_RT(uint8_t program) noexcept
{
  // With nothing loaded there is nothing to change. (This used to bump `presetChangesPending_` first and never undo
  // it, which blocked note-on forever.)
  auto ptr = syncPresetsState_RT();
  if (ptr == nullptr) return;

  allOff_RT();

  uint16_t msbBank = channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectMSB);
  uint16_t lsbBank = channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectLSB);
  uint16_t bank = msbBank * 128u + lsbBank;

  // Loading a preset's samples means disk reads and large allocations, so do it on the work queue. Until it finishes,
  // `presetChangesPending_` keeps the render thread from rendering or starting voices. `dispatch_async_f` takes a plain
  // function, which avoids copying a block (and the Objective-C runtime) on the render thread.
  requestedPresetIndex_.store(ptr->locatePresetIndex(bank, program), std::memory_order_release);
  ++presetChangesPending_;
  dispatch_async_f(workQueue_, this, &Engine::usePresetRequest_WQ);
}

void
Engine::initialize(Float sampleRate) noexcept
{
  sampleRate_ = sampleRate;
  minimumNoteDurationSamples_ = minimumNoteDurationMilliseconds_ * sampleRate / 1'000_F;
  renderingTimeBudgetIntervalNanoseconds_ = uint64_t(1.0e9 / sampleRate);
  allOff_RT();
  for (size_t index = 0; index < traits::maxVoiceCount; ++index) {
    voices_[index].initialize(index, sampleRate);
  }
  parameters_.reset();
}

void
Engine::stopAllExclusiveVoices_RT(int exclusiveClass) noexcept
{
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ++pos) {
    auto voiceIndex = *pos;
    if (voices_[voiceIndex].exclusiveClass() == exclusiveClass) {
      voices_[voiceIndex].releaseKeyViaExclusiveClass();
    }
  }
}

void
Engine::stopSameKeyVoices_RT(int eventKey) noexcept
{
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    auto voiceIndex = *pos;
    if (voices_[voiceIndex].initiatingKey() == eventKey) {
      pos = stopVoice_RT(voiceIndex);
    } else {
      ++pos;
    }
  }
}

size_t
Engine::startVoice_RT(const Config& config) noexcept
{
  os_signpost_interval_begin(log_, startVoiceSignpost_, "startVoice_RT");
  if (!config.samples()) {
    // Should not happen: a preset only becomes active once its samples are loaded.
    os_log_error(log_, "startVoice_RT - zone has no samples");
    os_signpost_interval_end(log_, startVoiceSignpost_, "startVoice_RT");
    return Voice::noPartner;
  }

  auto voiceIndex = oldestVoiceIndices_.voiceAcquire();
  os_log_debug(log_, "startVoice_RT - %lu", voiceIndex);
  // The voice may have been stolen from a stereo pair: its old partner carries on alone with its own pitch.
  unlinkStereoPartner_RT(voiceIndex);
  voices_[voiceIndex].configure(config, channelState_);
  parameters_.applyChanged(voices_[voiceIndex].state());
  voices_[voiceIndex].start();
  shareActiveVoiceCount_RT();
  os_signpost_interval_end(log_, startVoiceSignpost_, "startVoice_RT");
  return voiceIndex;
}

void
Engine::linkStereoPairs_RT(const Preset::ConfigCollection& configs,
                           const std::array<size_t, Preset::maxConfigsPerNote>& voiceIndices) noexcept
{
  // SF2.01 7.10: "If sfSampleType indicates a left or right sample, then wSampleLink is the sample header index of the
  // associated right or left stereo sample respectively. Both samples should be played entirely synchronously, with
  // their pitch controlled by the right sample's generators." Pair each right config with the left config it links to
  // (and that links back), from the same preset zone. Each voice joins at most one pair ("no instrument should be
  // designed in which it is possible to activate more than one instance of a particular stereo pair").
  for (size_t right = 0; right < configs.size(); ++right) {
    auto rightVoice = voiceIndices[right];
    if (rightVoice == Voice::noPartner || voices_[rightVoice].partner() != Voice::noPartner) continue;
    for (size_t left = 0; left < configs.size(); ++left) {
      auto leftVoice = voiceIndices[left];
      if (left == right || leftVoice == Voice::noPartner || leftVoice == rightVoice) continue;
      if (voices_[leftVoice].partner() != Voice::noPartner) continue;
      if (!configs[right].isStereoRightOf(configs[left])) continue;
      // With a small voice limit, a later config may have stolen an earlier one's voice. Only link two live voices.
      if (!voices_[rightVoice].isActive() || !voices_[leftVoice].isActive()) continue;
      voices_[rightVoice].linkStereoPartner(leftVoice, true);
      voices_[leftVoice].linkStereoPartner(rightVoice, false);
      break;
    }
  }
}

void
Engine::unlinkStereoPartner_RT(size_t voiceIndex) noexcept
{
  auto partner = voices_[voiceIndex].partner();
  if (partner == Voice::noPartner) return;
  voices_[partner].unlinkStereoPartner();
  voices_[voiceIndex].unlinkStereoPartner();
}

OldestVoiceCollection::iterator
Engine::stopVoice_RT(size_t voiceIndex) noexcept
{
  os_signpost_interval_begin(log_, stopVoiceSignpost_, "stopVoice_RT");
  os_log_debug(log_, "stopVoice_RT - %lu", voiceIndex);
  voices_[voiceIndex].stop();
  unlinkStereoPartner_RT(voiceIndex);
  auto pos = oldestVoiceIndices_.voiceRelease(voiceIndex);
  shareActiveVoiceCount_RT();
  os_signpost_interval_end(log_, stopVoiceSignpost_, "stopVoice_RT");
  return pos;
}

void
Engine::bumpLastLoadFinished_WQ() noexcept
{
  os_log_debug(log_, "bumpLastLoadFinished_WQ");
  auto param = [parameterTree_ parameterWithAddress: DSPHeaders::valueOf(ParameterAddress::lastLoadFinished)];
  lastLoadFinishedCounter_ += traits::lastLoadFinishedChange;
  [param setValue: AUValue(lastLoadFinishedCounter_)];
}

void
Engine::resetAllControllers_RT() noexcept
{
  // CC 121 resets controllers, not notes (MIDI RP-015): sounding voices keep playing with the reset values. The pedals
  // are among the controllers reset, so notes held only by sustain or sostenuto are released as if the pedal had been
  // lifted. (This used to call `reset_RT`, which also stopped every voice and reset RPN values such as pitch wheel
  // sensitivity.)
  auto previousPedalState = channelState_.pedalState();
  channelState_.resetControllers();
  notifyActiveVoicesChannelStateChanged_RT();
  if (previousPedalState.sustainPedalActive || previousPedalState.sostenutoPedalActive) {
    applyPedals_RT();
  }
}

void
Engine::reset_RT() noexcept
{
  allOff_RT();
  channelState_.reset();
}

void
Engine::parameterValueChanged(AUParameter* parameter, AUValue value) noexcept
{
  os_log_debug(log_, "parameterValueChanged - %llu %{public}s %f", parameter.address, parameter.identifier.UTF8String, value);
  auto rawIndex = parameter.address;
  if (rawIndex < 0) return;
  if (rawIndex < DSPHeaders::valueOf(Entity::Generator::Index::numValues)) {
    parameters_.setLiveValue(Entity::Generator::Index(rawIndex), value);
  } else if (rawIndex >= DSPHeaders::valueOf(ParameterAddress::firstParameterAddress) &&
             rawIndex < DSPHeaders::valueOf(ParameterAddress::lastParameterAddressPlusOne)) {
    auto address = ParameterAddress(rawIndex);
    switch (address) {
      case ParameterAddress::portamentoModeEnabled:
        setPortamentoModeEnabled(DSPHeaders::toBool(value));
        break;
      case ParameterAddress::portamentoRate:
        setPortamentoRate(value >= 0 ? size_t(value) : 0);
        break;
      case ParameterAddress::oneVoicePerKeyModeEnabled:
        setOneVoicePerKeyModeEnabled(DSPHeaders::toBool(value));
        break;
      case ParameterAddress::polyphonicModeEnabled:
        setPhonicMode(DSPHeaders::toBool(value) ?
                      SF2::Render::Engine::Engine::PhonicMode::poly :
                      SF2::Render::Engine::Engine::PhonicMode::mono);
        break;
      case ParameterAddress::retriggerModeEnabled:
        setRetriggerModeEnabled(DSPHeaders::toBool(value));
        break;
      default: break;
    }
  }
}

AUValue
Engine::provideParameterValue(AUParameter* parameter) const noexcept
{
  auto rawIndex = parameter.address;
  AUValue value = 0.0;
  if (rawIndex >= 0 && rawIndex < DSPHeaders::valueOf(Entity::Generator::Index::numValues)) {
    auto index = Entity::Generator::Index(rawIndex);
    const auto& def = Entity::Generator::Definition::definition(index);
    value = def.clamp(parameters_.getLiveValue(index));
  } else if (rawIndex >= DSPHeaders::valueOf(ParameterAddress::firstParameterAddress) &&
             rawIndex < DSPHeaders::valueOf(ParameterAddress::lastParameterAddressPlusOne)) {
    auto address = ParameterAddress(rawIndex);
    switch (address) {
      case ParameterAddress::portamentoModeEnabled:
        value = DSPHeaders::fromBool(portamentoModeEnabled());
        break;
      case ParameterAddress::portamentoRate:
        value = AUValue(portamentoRate());
        break;
      case ParameterAddress::oneVoicePerKeyModeEnabled:
        value = DSPHeaders::fromBool(oneVoicePerKeyModeEnabled());
        break;
      case ParameterAddress::polyphonicModeEnabled:
        value = DSPHeaders::fromBool(polyphonicModeEnabled());
        break;
      case ParameterAddress::activeVoiceCount:
        // Read the shared copy: the voice collection itself belongs to the render thread.
        return AUValue(activeVoiceCountShared_.load(std::memory_order_relaxed));
      case ParameterAddress::retriggerModeEnabled:
        value = DSPHeaders::fromBool(retriggerModeEnabled());
        break;
      case ParameterAddress::isRendering:
        value = DSPHeaders::fromBool(isRendering());
        break;
      case ParameterAddress::activeProgramIndex:
        value = AUValue(activeProgramIndex());
        break;
      case ParameterAddress::activeBankIndex:
        value = AUValue(activeBankIndex());
        break;
      case ParameterAddress::activePresetIndex:
        value = AUValue(activePresetIndex());
        break;
      case ParameterAddress::lastLoadFinished:
        value = lastLoadFinishedCounter_;
        break;
      default: break;
    }
  }

  os_log_debug(log_, "provideValue - %llu %{public}s %f", parameter.address, parameter.identifier.UTF8String, value);
  return value;
}

AUParameter*
Engine::makeGeneratorParameter(Entity::Generator::Index index) noexcept
{
  const auto& definition = Entity::Generator::Definition::definition(index);
  NSString* name = [NSString stringWithUTF8String:definition.name().data()];
  // The same range that `LiveGeneratorParameters::setLiveValue` accepts, which is wider than the spec's for a few
  // generators.
  auto range = LiveGeneratorParameters::liveValueRange(index);
  auto flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
  return [AUParameterTree createParameterWithIdentifier:name
                                                   name:name
                                                address:AUParameterAddress(DSPHeaders::valueOf(index))
                                                    min:AUValue(range.min)
                                                    max:AUValue(range.max)
                                                   unit:AudioUnitParameterUnit::kAudioUnitParameterUnit_Generic
                                               unitName:nullptr
                                                  flags:flags
                                           valueStrings:nullptr
                                    dependentParameters:nullptr];
}

AUParameter*
Engine::makeBooleanParameter(NSString* name, ParameterAddress address, bool value) noexcept
{
  auto flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
  auto param = [AUParameterTree createParameterWithIdentifier:name
                                                         name:name
                                                      address:DSPHeaders::valueOf(address)
                                                          min:0
                                                          max:1
                                                         unit:kAudioUnitParameterUnit_Boolean
                                                     unitName:nullptr
                                                        flags:flags
                                                 valueStrings:nullptr
                                          dependentParameters:nullptr];
  param.value = DSPHeaders::fromBool(value);
  return param;
}

void
Engine::makeTree() noexcept
{
  os_log_debug(log_, "makeTree BEGIN");

  // This is a bit too large due to various unused generators found in the spec.
  auto capacity = NSUInteger(traits::parameterTreeSize);
  auto definitions = [[NSMutableArray alloc] initWithCapacity:capacity];

  // Add definitions for all generators that are used by the SF2Lib engine. The first address will be
  // Generator::Index::startAddressOffset (0), and the last will be Generator::Index::overridingRootKey (58).
  // Note that not all addresses between 0 and 58 are valid; some of the Generator:Index values are tagged as unused,
  // and there will be no parameter defined for those.
  for (auto index : Entity::Generator::IndexIterator()) {
    const auto& definition = Entity::Generator::Definition::definition(index);
    if (definition.valueKind() == Entity::Generator::Definition::ValueKind::UNUSED) {
      continue;
    }

    auto param = makeGeneratorParameter(index);
    [definitions addObject:param];
  }

  // Add definitions for the MIDI continuous controllers (CC) defined in the SF2 spec that can affect SF2Lib engine
  // rendering.
  [definitions addObject:makeBooleanParameter(@"portamentoModeEnabled",
                                              ParameterAddress::portamentoModeEnabled,
                                              portamentoModeEnabled())];
  [definitions addObject:makeBooleanParameter(@"oneVoicePerKeyModeEnabled",
                                              ParameterAddress::oneVoicePerKeyModeEnabled,
                                              oneVoicePerKeyModeEnabled())];
  [definitions addObject:makeBooleanParameter(@"polyphonicModeEnabled",
                                              ParameterAddress::polyphonicModeEnabled,
                                              polyphonicModeEnabled())];
  [definitions addObject:makeBooleanParameter(@"retriggerModeEnabled",
                                              ParameterAddress::retriggerModeEnabled,
                                              retriggerModeEnabled())];
  [definitions addObject: makeBooleanParameter(@"isRendering",
                                               ParameterAddress::isRendering,
                                               isRendering())];

  auto flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
  auto param = [AUParameterTree createParameterWithIdentifier:@"portamentoRate"
                                                         name:@"portamentoRate"
                                                      address:DSPHeaders::valueOf(ParameterAddress::portamentoRate)
                                                          min:0
                                                          max:60000
                                                         unit:kAudioUnitParameterUnit_Milliseconds
                                                     unitName:nullptr
                                                        flags:flags
                                                 valueStrings:nullptr
                                          dependentParameters:nullptr];
  param.value = AUValue(portamentoRate());
  [definitions addObject:param];

  flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_MeterReadOnly;

  // Report out various read-only states

  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"activeVoiceCount"
                                                                         name:@"activeVoiceCount"
                                                                      address:DSPHeaders::valueOf(ParameterAddress::activeVoiceCount)
                                                                          min:0
                                                                          max:AUValue(traits::maxVoiceCount)
                                                                         unit:kAudioUnitParameterUnit_Generic
                                                                     unitName:nullptr
                                                                        flags:flags
                                                                 valueStrings:nullptr
                                                          dependentParameters:nullptr]];

  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"activeProgramIndex"
                                                                   name:@"activeProgramIndex"
                                                                address:DSPHeaders::valueOf(ParameterAddress::activeProgramIndex)
                                                                    min:0
                                                                    max:127
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];

  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"activeBankIndex"
                                                                   name:@"activeBankIndex"
                                                                address:DSPHeaders::valueOf(ParameterAddress::activeBankIndex)
                                                                    min:0
                                                                    max:127
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];

  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"activePresetIndex"
                                                                   name:@"activePresetIndex"
                                                                address:DSPHeaders::valueOf(ParameterAddress::activePresetIndex)
                                                                    min:0
                                                                    max:65535
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];

  // We do not care about actual value, only that a change took place in the engine. Should we use a binary flip/flop?
  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"lastLoadFinished"
                                                                    name:@"lastLoadFinished"
                                                                 address:DSPHeaders::valueOf(ParameterAddress::lastLoadFinished)
                                                                     min:traits::minLastLoadFinished
                                                                     max:traits::maxLastLoadFinished
                                                                    unit:kAudioUnitParameterUnit_Generic
                                                                unitName:nullptr
                                                                   flags:flags
                                                            valueStrings:nullptr
                                                     dependentParameters:nullptr]];

  parameterTree_ = [AUParameterTree createTreeWithChildren:definitions];

  parameterTree_.implementorValueObserver = ^(AUParameter* parameter, AUValue value) {
    parameterValueChanged(parameter, value);
  };

  parameterTree_.implementorValueProvider = ^(AUParameter* parameter) {
    return provideParameterValue(parameter);
  };

  os_log_debug(log_, "makeTree END");
}
