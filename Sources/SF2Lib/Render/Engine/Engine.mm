// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include <cstdint>
#include <vector>

#include "SF2Util/Base64.hpp"
#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/LoadPresetSysExPayload.hpp"
#include "SF2File/IO/File.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

Engine::Engine(Float sampleRate, size_t voiceCountLimit, Interpolator interpolator, double renderingTimeBudgetScaling,
               size_t minimumNoteDurationMilliseconds) noexcept
  : super(Log::create("Engine")),
    sampleRate_{sampleRate},
    minimumNoteDurationMilliseconds_{minimumNoteDurationMilliseconds},
    parameters_{},
    oldestVoiceIndices_{},
    voiceCountLimit_{voiceCountLimit},
    renderSignpost_{os_signpost_id_generate(log_)},
    noteOnSignpost_{os_signpost_id_generate(log_)},
    noteOffSignpost_{os_signpost_id_generate(log_)},
    startVoiceSignpost_{os_signpost_id_generate(log_)},
    stopVoiceSignpost_{os_signpost_id_generate(log_)},
    renderingTimeBudgetScaling_{renderingTimeBudgetScaling},
    workQueue_{dispatch_queue_create("SF2Lib::Engine", DISPATCH_QUEUE_SERIAL)}
{
  assert(voiceCountLimit <= traits::maxVoiceCount);

  durationBuckets_.reserve(voiceCountLimit);

  for (size_t voiceIndex = 0; voiceIndex < voiceCountLimit; ++voiceIndex) {
    voices_[voiceIndex].initialize(voiceIndex, sampleRate, interpolator);
  }

  makeTree();
}

Engine::~Engine() noexcept
{
  os_log_info(log_, "~Engine");
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
Engine::activePresetName() const noexcept
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

void
Engine::concludeUsePresetWithIndex_RT(size_t index)
{
  assert(presetChangesPending_.load() > 0);

  auto ptr = presetsState();
  if (ptr) {
    ptr->changeActivePreset(index);
  }

  parameters_.reset();
  bumpLastLoadFinished_RT();
  --presetChangesPending_;

  auto presetName = ptr->hasActivePreset() ? ptr->activePreset().configuration().name() : "???";
  NSString* name = [NSString stringWithCString:presetName.c_str() encoding:NSUTF8StringEncoding];
  os_log_info(log_, "concludeUsePresetWithIndex_RT END - %{public}@", name);
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
    auto ptr = presetsState();
    if (ptr && ptr->hasActivePreset()) {

      ptr->deletePast();

      if (channelState_.pedalState().softPedalActive) {
        velocity /= 2;
      }

      auto configs = ptr->activePreset().find(key, velocity);

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

      for (const Config& config : configs) {
        startVoice_RT(config);
      }
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
    voice.releaseKey(releaseKeyState);
  });
}

void
Engine::renderInto(Mixer mixer, AUAudioFrameCount frameCount) noexcept
{
  if (activeVoiceCount() == 0) return;

  auto timeBudget = timeBudgetNanoseconds(frameCount);
  auto entryTime = Utils::Timer::now();

  // Iterate over the active voices -- the voices are ordered from newest to oldest. If we run out of time we will stop
  // the oldest ones.
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    auto voiceIndex = *pos;

    auto& voice{voices_[voiceIndex]};
    if (voice.isActive()) {
      if (Utils::Timer::delta(entryTime) < timeBudget) {
        voice.renderInto(mixer, frameCount);
      } else {
        voice.stop();
      }
    } else {
      os_log_error(log_, "renderInto - encountered active voice that is not active - %lu", voiceIndex);
    }

    if (voice.isDone()) {
      pos = stopVoice_RT(voiceIndex);
    } else {
      ++pos;
    }
  }
}

AUAudioFrameCount
Engine::doParameterEvent(const AUParameterEvent& event, AUAudioFrameCount duration) noexcept {
  // NOTE: this is running in the real-time render thread.
  auto rawIndex = event.parameterAddress;
  auto value = event.value;
  if (rawIndex < 0) return 0;
  if (rawIndex < valueOf(Entity::Generator::Index::numValues)) {
    auto index = Entity::Generator::Index(rawIndex);
    parameters_.setLiveValue(index, value);
    notifyParameterChanged_RT(index);
    return duration;
  } else if (rawIndex >= valueOf(ParameterAddress::firstParameterAddress) &&
             rawIndex < valueOf(ParameterAddress::lastParameterAddressPlusOne)) {
    auto address = ParameterAddress(rawIndex);
    switch (address) {
      case ParameterAddress::portamentoModeEnabled:
        setPortamentoModeEnabled(SF2::toBool(value));
        break;
      case ParameterAddress::portamentoRate:
        setPortamentoRate(size_t(value));
        break;
      case ParameterAddress::oneVoicePerKeyModeEnabled:
        setOneVoicePerKeyModeEnabled(SF2::toBool(value));
        break;
      case ParameterAddress::polyphonicModeEnabled:
        setPhonicMode(SF2::toBool(value) ? Engine::PhonicMode::poly : Engine::PhonicMode::mono);
        break;
      case ParameterAddress::activeVoiceCount:
        break;
      case ParameterAddress::retriggerModeEnabled:
        setRetriggerModeEnabled(SF2::toBool(value));
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
  }

  [[parameterTree_ parameterWithAddress: valueOf(ParameterAddress::isRendering)] setValue: SF2::fromBool(state)];
}

void
Engine::doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept
{
  os_log_info(log_, "doMIDIEvent BEGIN - %d", midiEvent.length);

  if (midiEvent.length < 1) {
    os_log_info(log_, "doMIDIEvent BEGIN - no bytes");
    return;
  }

  if (midiEvent.data[0] < 0x80) {
    os_log_info(log_, "doMIDIEvent END - invalid first byte %d", midiEvent.data[0]);
    return;
  }

  auto event = MIDI::CoreEvent(midiEvent.data[0] < SF2::valueOf(MIDI::CoreEvent::systemExclusive)
                               ? (midiEvent.data[0] & SF2::valueOf(MIDI::CoreEvent::systemExclusive))
                               : midiEvent.data[0]);
  switch (event) {
    case MIDI::CoreEvent::noteOff:
      os_log_info(log_, "doMIDIEvent noteOff");
      if (midiEvent.length > 1) {
        noteOff_RT(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::noteOn:
      if (midiEvent.length > 1) {
        auto velocity = midiEvent.length == 3 ? midiEvent.data[2] : 0;
        if (velocity > 0) {
          os_log_info(log_, "doMIDIEvent noteOn");
          noteOn_RT(midiEvent.data[1], velocity);
        } else {
          os_log_info(log_, "doMIDIEvent noteOff (zero velocity noteOn");
          noteOff_RT(midiEvent.data[1]);
        }
      }
      break;

    case MIDI::CoreEvent::keyPressure:
      os_log_info(log_, "doMIDIEvent keyPressure");
      if (midiEvent.length == 3) {
        channelState_.setNotePressure(midiEvent.data[1], midiEvent.data[2]);
        notifyActiveVoicesChannelStateChanged_RT();
      }
      break;

    case MIDI::CoreEvent::controlChange:
      os_log_info(log_, "doMIDIEvent controlChange");
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
      os_log_info(log_, "doMIDIEvent programChange");
      if (midiEvent.length >= 2) {
        changeProgram_RT(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::channelPressure:
      os_log_info(log_, "doMIDIEvent channelPressure");
      if (midiEvent.length >= 2) {
        channelState_.setChannelPressure(midiEvent.data[1]);
        notifyActiveVoicesChannelStateChanged_RT();
      }
      break;

    case MIDI::CoreEvent::pitchBend:
      os_log_info(log_, "doMIDIEvent pitchBend");
      if (midiEvent.length == 3) {
        int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
        channelState_.setPitchWheelValue(bend);
        notifyActiveVoicesChannelStateChanged_RT();
      }
      break;

    case MIDI::CoreEvent::systemExclusive:
      os_log_info(log_, "doMIDIEvent systemExclusive");
      if (midiEvent.data[1] == LoadPresetSysExPayload::manufacturerValue &&
          midiEvent.data[midiEvent.length - 1] == SF2::valueOf(MIDI::CoreEvent::EOX)) {
        switch (midiEvent.data[2]) {
          case LoadPresetSysExPayload::modelPathPayload:
            if (!loadFileAndPresetFromSysEx_RT(midiEvent)) {
              os_log_info(log_, "doMIDIEvent - systemExclusive ignored due to length < 6");
            }
            break;

          case LoadPresetSysExPayload::modelBookmarkPayload:
            if (!loadBookmarkAndPresetFromSysEx_RT(midiEvent)) {
              os_log_info(log_, "doMIDIEvent - systemExclusive ignored due to length < 6");
            }
            break;

          default:
            os_log_info(log_, "doMIDIEvent - systemExclusive ignored");
            break;
        }
      }
      break;

    case MIDI::CoreEvent::reset:
      os_log_info(log_, "doMIDIEvent reset");
      reset_RT();
      break;

    default:
      os_log_info(log_, "doMIDIEvent - ignored %hhX", midiEvent.data[0]);
      break;
  }

  os_log_info(log_, "doMIDIEvent END");
}

void
Engine::processChannelMessage_RT(MIDI::ControlChange channelMessage, uint8_t value) noexcept
{
  os_log_info(log_, "processChannelMessage_RT - %d value: %d", channelMessage, value);
  switch (channelMessage) {
    case MIDI::ControlChange::allSoundOff:
      allOff_RT();
      break;

    case MIDI::ControlChange::resetAllControllers:
      reset_RT();
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
Engine::loadFileAndPresetFromSysEx_RT(const AUMIDIEvent& midiEvent) noexcept {
  os_log_info(log_, "loadFileAndPresetFromSysEx_RT BEGIN");

  if (midiEvent.length < LoadPresetSysExPayload::minPayloadSize) {
    os_log_error(log_, "loadFileAndPresetFromSysEx_RT END - invalid midi payload %d", midiEvent.length);
    return false;
  }

  // Stop all existing voices and block future ones from starting.
  allOff_RT();
  // Increment number of items in workQueue
  ++presetChangesPending_;

  const uint8_t* bytes = midiEvent.data;
  auto payload = reinterpret_cast<const LoadPresetSysExPayload*>(bytes);
  auto overrideCount = payload->overrideCount;
  auto pos1 = reinterpret_cast<const SF2::MIDI::GeneratorOverride*>(payload + 1);
  auto overrides = std::vector<MIDI::GeneratorOverride>(pos1, pos1 + overrideCount);
  auto pathStart = reinterpret_cast<const uint8_t*>(pos1 + overrideCount);
  auto pathCount = size_t((bytes + midiEvent.length) - pathStart) - 1;

  // Let another thread deal with the the loading -- we are on the render thread and need to move on.
  __block auto path = pathCount == 0 ? std::string("") : Utils::Base64::decode(pathStart, pathCount);
  __block auto presetIndex = payload->presetIndex;
  dispatch_async(workQueue_, ^{ beginLoadFileAndPreset_RT(path, presetIndex); });

  os_log_info(log_, "loadFileAndPresetFromSysEx_RT END - true");
  return true;
}

bool
Engine::loadBookmarkAndPresetFromSysEx_RT(const AUMIDIEvent& midiEvent) noexcept {
  os_log_info(log_, "loadBookmarkAndPresetFromSysEx_RT BEGIN");

  if (midiEvent.length < LoadPresetSysExPayload::minPayloadSize) {
    os_log_error(log_, "loadBookmarkAndPresetFromSysEx_RT END - invalid midi payload %d", midiEvent.length);
    return false;
  }

  // Stop all existing voices and block future ones from starting.
  allOff_RT();
  // Increment number of items in workQueue
  ++presetChangesPending_;

  const uint8_t* bytes = midiEvent.data;
  auto payload = reinterpret_cast<const LoadPresetSysExPayload*>(bytes);
  auto overrideCount = payload->overrideCount;
  auto pos1 = reinterpret_cast<const SF2::MIDI::GeneratorOverride*>(payload + 1);
  auto overrides = std::vector<MIDI::GeneratorOverride>(pos1, pos1 + overrideCount);
  auto dataStart = const_cast<uint8_t*>(reinterpret_cast<const uint8_t*>(pos1 + overrideCount));
  auto dataCount = size_t((bytes + midiEvent.length) - dataStart) - 1;

  // Let another thread deal with the the loading -- we are on the render thread and need to move on.
  // NOTE: not sure why this cannot be done in the workQueue routine.
  NSData* data = [NSData dataWithBytesNoCopy:dataStart length:dataCount freeWhenDone:false];
  __block NSData* bookmark = [data initWithBase64EncodedData:data options:0];
  __block auto presetIndex = payload->presetIndex;
  dispatch_async(workQueue_, ^{ beginLoadBookmarkAndPreset_RT(bookmark, presetIndex); });

  os_log_info(log_, "loadBookmarkAndPresetFromSysEx_RT END - true");
  return true;
}

SF2::IO::File::LoadResponse
Engine::loadFileAndPreset(std::string path, size_t presetIndex) noexcept {
  ++presetChangesPending_;
  return beginLoadFileAndPreset_RT(path, presetIndex);
}

SF2::IO::File::LoadResponse
Engine::loadFileAndPreset(int fd, size_t presetIndex) noexcept {
  ++presetChangesPending_;
  return concludeLoad_RT(fd, presetIndex);
}

SF2::IO::File::LoadResponse
Engine::beginLoadFileAndPreset_RT(std::string path, size_t presetIndex) noexcept {
  os_log_info(log_, "beginLoadFileAndPreset_RT BEGIN");
  if (!path.empty()) {
    concludeLoad_RT(path, presetIndex);
  } else {
    concludeUsePresetWithIndex_RT(presetIndex);
  }
  auto response = presetsState_.load()->loadResponse();
  os_log_info(log_, "beginLoadFileAndPreset_RT END - %d", response);
  return response;
}

SF2::IO::File::LoadResponse
Engine::concludeLoad_RT(const std::string& path, size_t index) noexcept
{
  os_log_info(log_, "concludeLoad_RT - path: '%{public}s' index: %lu", path.c_str(), index);
  assert(presetChangesPending_.load() > 0);

  // Set new presets state for render thread to use. It will be responsible for deleting the old state when it is safe to do so.
  presetsState_.store(new PresetsState(path, index, presetsState_.load()));
  concludeUsePresetWithIndex_RT(index);

  auto response = presetsState_.load()->loadResponse();
  os_log_info(log_, "concludeLoad_RT END - %d", response);
  return response;
}

SF2::IO::File::LoadResponse
Engine::loadBookmarkAndPreset(NSData *bookmark, size_t presetIndex) noexcept {
  ++presetChangesPending_;
  return beginLoadBookmarkAndPreset_RT(bookmark, presetIndex);
}

SF2::IO::File::LoadResponse
Engine::beginLoadBookmarkAndPreset_RT(NSData* bookmark, size_t presetIndex) noexcept {
  os_log_info(log_, "loadBookmarkAndPreset BEGIN");

  NSError* error = nil;
  BOOL isStale = NO;
  NSURL* resolved = [NSURL URLByResolvingBookmarkData:bookmark
                                              options:0
                                        relativeToURL:nil
                                  bookmarkDataIsStale:&isStale
                                                error:&error];

  if (error != nil) {
    os_log_error(log_, "loadBookmarkAndPreset END - error from resolving bookmark data - %{public}@", error);
    return;
  } else if (resolved == nil) {
    os_log_error(log_, "loadBookmarkAndPreset END - failed to resolve bookmark data (no error)");
    return;
  } else {
    os_log_error(log_, "loadBookmarkAndPreset - resolved bookmark: %{public}@", resolved);
  }

  BOOL didStart = NO;
  if ([resolved respondsToSelector:@selector(startAccessingSecurityScopedResource)]) {
    didStart = [resolved startAccessingSecurityScopedResource];
  }

  error = nil;

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

    os_log_info(log_, "loading from resolved url - file descriptor: %d", fileHandle.fileDescriptor);

    concludeLoad_RT(fileHandle.fileDescriptor, presetIndex);
  }];

  if (didStart) {
    [resolved stopAccessingSecurityScopedResource];
  }

  auto response = presetsState_.load()->loadResponse();
  os_log_info(log_, "loadBookmarkAndPreset END - %d", response);
  return response;
}

SF2::IO::File::LoadResponse
Engine::concludeLoad_RT(int fd, size_t index) noexcept
{
  os_log_info(log_, "concludeLoad - fd: %d index: %lu", fd, index);
  assert(presetChangesPending_.load() > 0);

  // Set new presets state for render thread to use. It will be responsible for deleting the old state when it is safe to do so.
  presetsState_.store(new PresetsState(fd, index, presetsState_.load()));
  concludeUsePresetWithIndex_RT(index);

  auto response = presetsState_.load()->loadResponse();
  os_log_info(log_, "concludeLoad END - %d", response);
  return response;
}

std::vector<uint8_t>
Engine::createLoadFileUsePresetPayload(const std::string& filePath, size_t presetIndex,
                                       const MIDI::GeneratorOverrideVector& overrides) noexcept
{
  return LoadPresetSysExPayload::make(overrides, filePath, presetIndex);
}

std::vector<uint8_t>
Engine::createLoadBookmarkUsePresetPayload(const NSData* bookmark, size_t presetIndex,
                                           const std::vector<SF2::MIDI::GeneratorOverride>& overrides) noexcept
{
  return LoadPresetSysExPayload::make(overrides, bookmark, presetIndex);
}

std::array<uint8_t, 1>
Engine::createResetCommandPayload() noexcept
{
  return std::array<uint8_t, 1>{
    SF2::valueOf(MIDI::CoreEvent::reset)
  };
}

std::array<uint8_t, 3>
Engine::createChannelMessagePayload(MIDI::ControlChange channelMessage, uint8_t value) noexcept
{
  return std::array<uint8_t, 3>{
    SF2::valueOf(MIDI::CoreEvent::controlChange),
    SF2::valueOf(channelMessage),
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
    SF2::valueOf(MIDI::CoreEvent::controlChange),
    SF2::valueOf(MIDI::ControlChange::bankSelectMSB),
    bankMSB,
    SF2::valueOf(MIDI::CoreEvent::controlChange),
    SF2::valueOf(MIDI::ControlChange::bankSelectLSB),
    bankLSB,
    SF2::valueOf(MIDI::CoreEvent::programChange),
    program,
    0
  };
}

void
Engine::changeProgram_RT(uint8_t program) noexcept
{
  allOff_RT();
  ++presetChangesPending_;

  uint16_t msbBank = channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectMSB);
  uint16_t lsbBank = channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectLSB);
  uint16_t bank = msbBank * 128u + lsbBank;

  auto ptr = presetsState();
  if (ptr) {
    auto index = ptr->locatePresetIndex(bank, program);
    concludeUsePresetWithIndex_RT(index);
  }
}

void
Engine::initialize(Float sampleRate) noexcept
{
  sampleRate_ = sampleRate;
  renderingTimeBudgetIntervalNanoseconds_ = uint64_t(1.0 / sampleRate * 1.0e9);
  allOff_RT();
  for (auto& voice : voices_) {
    voice.setSampleRate(sampleRate);
  }
  parameters_.reset();
}

void
Engine::stopAllExclusiveVoices_RT(int exclusiveClass) noexcept
{
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    auto voiceIndex = *pos;
    if (voices_[voiceIndex].exclusiveClass() == exclusiveClass) {
      pos = stopVoice_RT(voiceIndex);
    } else {
      ++pos;
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

void
Engine::startVoice_RT(const Config& config) noexcept
{
  os_signpost_interval_begin(log_, startVoiceSignpost_, "startVoice_RT");
  auto voiceIndex = oldestVoiceIndices_.voiceAcquire();
  os_log_info(log_, "startVoice_RT - %lu", voiceIndex);
  voices_[voiceIndex].configure(config, channelState_);
  parameters_.applyChanged(voices_[voiceIndex].state());
  voices_[voiceIndex].start();
  updateActiveVoiceCount_RT();
  os_signpost_interval_end(log_, startVoiceSignpost_, "startVoice_RT");
}

OldestVoiceCollection::iterator
Engine::stopVoice_RT(size_t voiceIndex) noexcept
{
  os_signpost_interval_begin(log_, stopVoiceSignpost_, "stopVoice_RT");
  os_log_info(log_, "stopVoice_RT - %lu", voiceIndex);
  voices_[voiceIndex].stop();
  auto pos = oldestVoiceIndices_.voiceRelease(voiceIndex);
  os_signpost_interval_end(log_, stopVoiceSignpost_, "stopVoice_RT");
  updateActiveVoiceCount_RT();
  return pos;
}

void
Engine::updateActiveVoiceCount_RT() noexcept
{
  auto value = oldestVoiceIndices_.activeVoiceCount();
  os_log_info(log_, "updateActiveVoiceCount_RT - %ld", value);
  [[parameterTree_ parameterWithAddress: valueOf(ParameterAddress::activeVoiceCount)] setValue: AUValue(value)];
}

void
Engine::bumpLastLoadFinished_RT() noexcept
{
  os_log_info(log_, "bumpLastLoadFinished_RT");
  auto param = [parameterTree_ parameterWithAddress: valueOf(ParameterAddress::lastLoadFinished)];
  lastLoadFinishedCounter_ += traits::lastLoadFinishedChange;
  [param setValue: AUValue(lastLoadFinishedCounter_)];
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
  os_log_info(log_, "parameterValueChanged - %llu %{public}s %f", parameter.address, parameter.identifier.UTF8String, value);
  auto rawIndex = parameter.address;
  if (rawIndex < 0) return;
  if (rawIndex < valueOf(Entity::Generator::Index::numValues)) {
    parameters_.setLiveValue(Entity::Generator::Index(rawIndex), value);
  } else if (rawIndex >= valueOf(ParameterAddress::firstParameterAddress) &&
             rawIndex < valueOf(ParameterAddress::lastParameterAddressPlusOne)) {
    auto address = ParameterAddress(rawIndex);
    switch (address) {
      case ParameterAddress::portamentoModeEnabled:
        setPortamentoModeEnabled(SF2::toBool(value));
        break;
      case ParameterAddress::portamentoRate:
        setPortamentoRate(value >= 0 ? size_t(value) : 0);
        break;
      case ParameterAddress::oneVoicePerKeyModeEnabled:
        setOneVoicePerKeyModeEnabled(SF2::toBool(value));
        break;
      case ParameterAddress::polyphonicModeEnabled:
        setPhonicMode(SF2::toBool(value) ?
                      SF2::Render::Engine::Engine::PhonicMode::poly :
                      SF2::Render::Engine::Engine::PhonicMode::mono);
        break;
      case ParameterAddress::retriggerModeEnabled:
        setRetriggerModeEnabled(SF2::toBool(value));
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
  if (rawIndex >= 0 && rawIndex < valueOf(Entity::Generator::Index::numValues)) {
    auto index = Entity::Generator::Index(rawIndex);
    const auto& def = Entity::Generator::Definition::definition(index);
    value = def.clamp(parameters_.getLiveValue(index));
  } else if (rawIndex >= valueOf(ParameterAddress::firstParameterAddress) &&
             rawIndex < valueOf(ParameterAddress::lastParameterAddressPlusOne)) {
    auto address = ParameterAddress(rawIndex);
    switch (address) {
      case ParameterAddress::portamentoModeEnabled:
        value = SF2::fromBool(portamentoModeEnabled());
        break;
      case ParameterAddress::portamentoRate:
        value = AUValue(portamentoRate());
        break;
      case ParameterAddress::oneVoicePerKeyModeEnabled:
        value = SF2::fromBool(oneVoicePerKeyModeEnabled());
        break;
      case ParameterAddress::polyphonicModeEnabled:
        value = SF2::fromBool(polyphonicModeEnabled());
        break;
      case ParameterAddress::activeVoiceCount:
        return AUValue(oldestVoiceIndices_.activeVoiceCount());
      case ParameterAddress::retriggerModeEnabled:
        value = SF2::fromBool(retriggerModeEnabled());
        break;
      case ParameterAddress::isRendering:
        return isRendering();
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

  os_log_info(log_, "provideValue - %llu %{public}s %f", parameter.address, parameter.identifier.UTF8String, value);
  return value;
}

AUParameter*
Engine::makeGeneratorParameter(Entity::Generator::Index index) noexcept
{
  const auto& definition = Entity::Generator::Definition::definition(index);
  NSString* name = [NSString stringWithUTF8String:definition.name().data()];
  auto flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
  return [AUParameterTree createParameterWithIdentifier:name
                                                   name:name
                                                address:AUParameterAddress(valueOf(index))
                                                    min:AUValue(definition.valueRange().min)
                                                    max:AUValue(definition.valueRange().max)
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
                                                      address:valueOf(address)
                                                          min:0
                                                          max:1
                                                         unit:kAudioUnitParameterUnit_Boolean
                                                     unitName:nullptr
                                                        flags:flags
                                                 valueStrings:nullptr
                                          dependentParameters:nullptr];
  param.value = fromBool(value);
  return param;
}

void
Engine::makeTree() noexcept
{
  os_log_info(log_, "makeTree BEGIN");

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
                                                      address:valueOf(ParameterAddress::portamentoRate)
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
                                                                      address:valueOf(ParameterAddress::activeVoiceCount)
                                                                          min:0
                                                                          max:AUValue(voiceCountLimit())
                                                                         unit:kAudioUnitParameterUnit_Generic
                                                                     unitName:nullptr
                                                                        flags:flags
                                                                 valueStrings:nullptr
                                                          dependentParameters:nullptr]];

  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"activeProgramIndex"
                                                                   name:@"activeProgramIndex"
                                                                address:valueOf(ParameterAddress::activeProgramIndex)
                                                                    min:0
                                                                    max:127
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];

  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"activeBankIndex"
                                                                   name:@"activeBankIndex"
                                                                address:valueOf(ParameterAddress::activeBankIndex)
                                                                    min:0
                                                                    max:127
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];

  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"activePresetIndex"
                                                                   name:@"activePresetIndex"
                                                                address:valueOf(ParameterAddress::activePresetIndex)
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
                                                                 address:valueOf(ParameterAddress::lastLoadFinished)
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

  os_log_info(log_, "makeTree END");
}
