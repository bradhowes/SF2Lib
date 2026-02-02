// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include <cstdint>
#include <vector>

#include "SF2Util/Base64.hpp"
#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2File/IO/File.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

struct LoadPresetSysExPayload {
  static constexpr uint8_t manufacturerValue = 0x7E;
  static constexpr uint8_t modelPathPayload = 0x00; // the payload holds a path string to a file
  static constexpr uint8_t modelBookmarkPayload = 0x01; // the payload holds a bookmark to a file

  uint8_t sysExBegin;    // 0
  uint8_t manufacturer;  // 1
  uint8_t model;         // 2
  // Here lies 5 bytes of padding
  size_t presetIndex;    // 8
  size_t overrideCount;  // 16
  // SF2::MIDI::GeneratorOverride overrides[1];
  // char filePath[1];
  // uint8_t sysExEnd;   // 25 is smallest payload size

  static constexpr size_t minPayloadSize = 25;

  static std::vector<uint8_t> make(const SF2::MIDI::GeneratorOverrideVector& overrides,
                                   const std::string& filePath, size_t presetIndex) noexcept {
    auto encodedFilePath = filePath.empty() ? std::string("") : SF2::Utils::Base64::encode(filePath);
    auto payloadSize = (sizeof(LoadPresetSysExPayload)
                        + overrides.size() * sizeof(SF2::MIDI::GeneratorOverride)
                        + encodedFilePath.size()) + 1;
    auto bytes = std::vector<uint8_t>(payloadSize, 0);
    auto payload = reinterpret_cast<LoadPresetSysExPayload*>(bytes.data());
    payload->sysExBegin = SF2::valueOf(SF2::MIDI::CoreEvent::systemExclusive);
    payload->manufacturer = manufacturerValue;
    payload->model = modelPathPayload;
    payload->presetIndex = presetIndex;
    payload->overrideCount = overrides.size();
    auto pos1 = reinterpret_cast<SF2::MIDI::GeneratorOverride*>((bytes.data() + sizeof(LoadPresetSysExPayload)));
    auto pos2 = std::copy(overrides.begin(), overrides.end(), pos1);
    auto pos3 = reinterpret_cast<uint8_t*>(std::copy(encodedFilePath.begin(), encodedFilePath.end(),
                                                     reinterpret_cast<char*>(pos2)));
    *pos3++ = SF2::valueOf(SF2::MIDI::CoreEvent::EOX);

    assert(pos3 - bytes.data() == long(bytes.size()));
    assert(bytes.size() >= minPayloadSize);

    return bytes;
  }

  static std::vector<uint8_t> make(const SF2::MIDI::GeneratorOverrideVector& overrides,
                                   const NSData* bookmark, size_t presetIndex) noexcept {
    NSData* encodedBookmark = [bookmark base64EncodedDataWithOptions: 0];
    auto payloadSize = (sizeof(LoadPresetSysExPayload)
                        + overrides.size() * sizeof(SF2::MIDI::GeneratorOverride)
                        + encodedBookmark.length) + 1;
    auto bytes = std::vector<uint8_t>(payloadSize, 0);
    auto payload = reinterpret_cast<LoadPresetSysExPayload*>(bytes.data());
    payload->sysExBegin = SF2::valueOf(SF2::MIDI::CoreEvent::systemExclusive);
    payload->manufacturer = manufacturerValue;
    payload->model = modelBookmarkPayload;
    payload->presetIndex = presetIndex;
    payload->overrideCount = overrides.size();
    auto pos1 = reinterpret_cast<SF2::MIDI::GeneratorOverride*>((bytes.data() + sizeof(LoadPresetSysExPayload)));
    auto pos2 = reinterpret_cast<uint8_t*>(std::copy(overrides.begin(), overrides.end(), pos1));
    [encodedBookmark getBytes: pos2 length: encodedBookmark.length];
    auto pos3 = pos2 + encodedBookmark.length;
    *pos3++ = SF2::valueOf(SF2::MIDI::CoreEvent::EOX);

    assert(pos3 - bytes.data() == long(bytes.size()));
    assert(bytes.size() >= minPayloadSize);

    return bytes;
  }
};

Engine::Engine(Float sampleRate, size_t voiceCountLimit, Interpolator interpolator, double renderingTimeBudgetScaling,
               size_t minimumNoteDurationMilliseconds) noexcept
  : super(Log::create("Engine")),
    sampleRate_{sampleRate},
    minimumNoteDurationMilliseconds_{minimumNoteDurationMilliseconds},
    parameters_{},
    voiceCountLimit_{voiceCountLimit},
    oldestVoiceIndices_{voiceCountLimit},
    renderSignpost_{os_signpost_id_generate(log_)},
    noteOnSignpost_{os_signpost_id_generate(log_)},
    noteOffSignpost_{os_signpost_id_generate(log_)},
    startVoiceSignpost_{os_signpost_id_generate(log_)},
    stopVoiceSignpost_{os_signpost_id_generate(log_)},
    renderingTimeBudgetScaling_{renderingTimeBudgetScaling},
    workQueue_{dispatch_queue_create("SF2Lib::Engine", NULL)}
{
  assert(voiceCountLimit <= traits::maxVoiceCount);

  durationBuckets_.reserve(voiceCountLimit);

  for (size_t voiceIndex = 0; voiceIndex < voiceCountLimit; ++voiceIndex) {
    voices_[voiceIndex].initialize(voiceIndex, sampleRate, interpolator);
    if constexpr (traits::renderDurationCollectionEnabled) { durationBuckets_.emplace_back(0.0); }
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
  return activePreset_ < presets_.size();
}

std::string
Engine::activePresetName() const noexcept
{
  return hasActivePreset() ? presets_[activePreset_].configuration().name() : "";
}

int
Engine::activeProgramIndex() const noexcept
{
  return hasActivePreset() ? presets_[activePreset_].configuration().program() : -1;
}

int
Engine::activeBankIndex() const noexcept
{
  return hasActivePreset() ? presets_[activePreset_].configuration().bank() : -1;
}

int
Engine::activePresetIndex() const noexcept
{
  return hasActivePreset() ? int(activePreset_) : -1;
}

SF2::IO::File::LoadResponse
Engine::load(const std::string& path, size_t index) noexcept
{
  os_log_info(log_, "load - path: '%{public}s' index: %lu", path.c_str(), index);
  allOff();
  auto file = std::make_unique<IO::File>(path);
  auto response = file->load();
  if (response == IO::File::LoadResponse::ok) {
    presets_.clear();
    file_.swap(file);
    presets_.build(*file_);
    usePresetWithIndex(index);
  }

  os_log_info(log_, "load END - %d", response);
  return response;
}

SF2::IO::File::LoadResponse
Engine::load(int fd, size_t index) noexcept
{
  os_log_info(log_, "load - fd: %d index: %lu", fd, index);

  allOff();

  auto file = std::make_unique<IO::File>();
  auto response = file->load(fd);

  if (response == IO::File::LoadResponse::ok) {
    presets_.clear();
    file_.swap(file);
    presets_.build(*file_);
    usePresetWithIndex(index);
  }

  os_log_info(log_, "load END - %d", response);
  return response;
}

void
Engine::usePresetWithIndex(size_t index)
{
  allOff();
  if (index >= presets_.size()) {
    // Special case to flag no preset being used.
    index = presets_.size();
  }
  activePreset_ = index;
  parameters_.reset();
  bumpLastLoadFinished();
}

void
Engine::usePresetWithBankProgram(uint16_t bank, uint16_t program)
{
  auto index = presets_.locatePresetIndex(bank, program);
  usePresetWithIndex(index);
}

void
Engine::allOff() noexcept
{
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    pos = stopVoice(*pos);
  }
}

void
Engine::noteOn(int key, int velocity) noexcept
{
  if (! hasActivePreset()) return;
  os_signpost_interval_begin(log_, noteOnSignpost_, "noteOn");

  if (channelState_.pedalState().softPedalActive) {
    velocity /= 2;
  }

  auto configs = presets_[activePreset_].find(key, velocity);

  // Stop any existing voice with the same exclusiveClass value.
  for (const Config& config : configs) {
    auto exclusiveClass{config.exclusiveClass()};
    if (exclusiveClass > 0) {
      stopAllExclusiveVoices(exclusiveClass);
    }
    if (oneVoicePerKeyModeEnabled_) {
      stopSameKeyVoices(config.eventKey());
    }
  }

  for (const Config& config : configs) {
    startVoice(config);
  }
  os_signpost_interval_end(log_, noteOnSignpost_, "noteOn");
}

void
Engine::noteOff(int key) noexcept
{
  os_signpost_interval_begin(log_, noteOffSignpost_, "noteOff");
  visitActiveVoice([=](Voice& voice, const Voice::ReleaseKeyState& releaseKeyState) {
    if (voice.initiatingKey() == key) {
      voice.releaseKey(releaseKeyState);
    }
  });
  os_signpost_interval_end(log_, noteOffSignpost_, "noteOff");
}

void
Engine::applySostenutoPedal() noexcept
{
  visitActiveVoice([](Voice& voice, const Voice::ReleaseKeyState&) {
    if (voice.isKeyDown()) voice.useSostenuto();
  });
}

void
Engine::releaseKeys() noexcept
{
  visitActiveVoice([](Voice& voice, const Voice::ReleaseKeyState& releaseKeyState) {
    voice.releaseKey(releaseKeyState);
  }, Voice::ReleaseKeyState{0u, MIDI::ChannelState::PedalState()});
}

void
Engine::applyPedals() noexcept
{
  visitActiveVoice([](Voice& voice, const Voice::ReleaseKeyState& releaseKeyState) {
    voice.releaseKey(releaseKeyState);
  });
}

void
Engine::renderInto(Mixer mixer, AUAudioFrameCount frameCount) noexcept
{
  auto voiceCount = activeVoiceCount();
  if (voiceCount == 0) {
    if constexpr (traits::renderDurationCollectionEnabled) { updateDurationParameters(); }
    return;
  }

  if constexpr (traits::renderDurationCollectionEnabled) {
    os_signpost_interval_begin(log_, renderSignpost_, "renderInto", "voices: %lu", voiceCount);
  }

  uint64_t timeBudgetNanoseconds = renderingTimeBudgetScaling_ > 0.0
  ? (frameCount * renderingTimeBudgetIntervalNanoseconds_ * renderingTimeBudgetScaling_)
  : 0xFFFFFFFFFFFFFFFFL;

  auto entryTime = Utils::Timer::now();

  // Iterate over the active voices -- the voices are ordered from newest to oldest. If we run out of time we will stop
  // the oldest ones.
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    auto voiceIndex = *pos;
    auto& voice{voices_[voiceIndex]};
    if (voice.isActive()) {
      if (Utils::Timer::delta(entryTime) < timeBudgetNanoseconds) {
        voice.renderInto(mixer, frameCount);
      } else {
        voice.stop();
      }
    }
    if (voice.isDone()) {
      pos = stopVoice(voiceIndex);
    } else {
      ++pos;
    }
  }

  if constexpr (traits::renderDurationCollectionEnabled) {
    durationBuckets_[voiceCount - 1] = Utils::Timer::delta(entryTime);
    os_signpost_interval_end(log_, renderSignpost_, "renderInto", "voices: %lu", voiceCount);
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
    notifyParameterChanged(index);
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
        noteOff(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::noteOn:
      os_log_info(log_, "doMIDIEvent noteOn");
      if (midiEvent.length == 3) {
        noteOn(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::keyPressure:
      os_log_info(log_, "doMIDIEvent keyPressure");
      if (midiEvent.length == 3) {
        channelState_.setNotePressure(midiEvent.data[1], midiEvent.data[2]);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::controlChange:
      os_log_info(log_, "doMIDIEvent controlChange");
      if (midiEvent.length == 3) {
        auto what = MIDI::ControlChange(midiEvent.data[1]);
        auto data = midiEvent.data[2];
        if (midiEvent.data[1] < 120) {
          processControlChange(what, data);
        } else {
          processChannelMessage(what, data);
        }
      }
      break;

    case MIDI::CoreEvent::programChange:
      os_log_info(log_, "doMIDIEvent programChange");
      if (midiEvent.length >= 2) {
        changeProgram(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::channelPressure:
      os_log_info(log_, "doMIDIEvent channelPressure");
      if (midiEvent.length >= 2) {
        channelState_.setChannelPressure(midiEvent.data[1]);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::pitchBend:
      os_log_info(log_, "doMIDIEvent pitchBend");
      if (midiEvent.length == 3) {
        int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
        channelState_.setPitchWheelValue(bend);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::systemExclusive:
      os_log_info(log_, "doMIDIEvent systemExclusive");
      if (midiEvent.data[1] == LoadPresetSysExPayload::manufacturerValue &&
          midiEvent.data[midiEvent.length - 1] == SF2::valueOf(MIDI::CoreEvent::EOX)) {
        switch (midiEvent.data[2]) {
          case LoadPresetSysExPayload::modelPathPayload:
            if (!loadFileAndPresetFromSysEx(midiEvent)) {
              os_log_info(log_, "doMIDIEvent - systemExclusive ignored due to length < 6");
            }
            break;

          case LoadPresetSysExPayload::modelBookmarkPayload:
            if (!loadBookmarkAndPresetFromSysEx(midiEvent)) {
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
      reset();
      break;

    default:
      os_log_info(log_, "doMIDIEvent - ignored %hhX", midiEvent.data[0]);
      break;
  }

  os_log_info(log_, "doMIDIEvent END");
}

void
Engine::processChannelMessage(MIDI::ControlChange channelMessage, uint8_t value) noexcept
{
  os_log_info(log_, "processChannelMessage - %d value: %d", channelMessage, value);
  switch (channelMessage) {
    case MIDI::ControlChange::allSoundOff:
      allOff();
      break;

    case MIDI::ControlChange::resetAllControllers:
      reset();
      break;

//    case MIDI::ControlChange::localControl:
//      break;

    case MIDI::ControlChange::allNotesOff:
      releaseKeys();
      break;

    case MIDI::ControlChange::omniOff:
      allOff();
      break;

    case MIDI::ControlChange::omniOn:
      allOff();
      break;

    case MIDI::ControlChange::monoOn:
      allOff();
      setPhonicMode(PhonicMode::mono);
      break;

    case MIDI::ControlChange::polyOn:
      allOff();
      setPhonicMode(PhonicMode::poly);
      break;

    default: break;
  }
}

void
Engine::processControlChange(MIDI::ControlChange cc, uint8_t value) noexcept
{
  auto previousPedalState = channelState_.pedalState();

  // Delegate the processing of the CC values. If a value was actually changed, then notify the active voices so that
  // they can update their generators that rely on CC values.
  if (channelState_.setContinuousControllerValue(cc, value)) {
    notifyActiveVoicesChannelStateChanged();
  }

  // Now check if there is a pedal change that can affect note off responses in a voice.
  auto currentPedalState = channelState_.pedalState();
  auto doRelease = false;

  if (!previousPedalState.sostenutoPedalActive) {
    if (currentPedalState.sostenutoPedalActive) {
      applySostenutoPedal();
    }
  } else {
    doRelease = !currentPedalState.sostenutoPedalActive;
  }

  if (previousPedalState.sustainPedalActive && !currentPedalState.sustainPedalActive) {
    doRelease = true;
  }

  if (doRelease) {
    applyPedals();
  }
}

void
Engine::notifyParameterChanged(Entity::Generator::Index index) noexcept
{
  visitActiveVoice([&](Voice& voice, const Voice::ReleaseKeyState&) {
    parameters_.applyOneGenerator(voice.state(), index);
  });
}

void
Engine::notifyActiveVoicesChannelStateChanged() noexcept
{
  visitActiveVoice([&](Voice& voice, const Voice::ReleaseKeyState&) { voice.channelStateChanged(channelState_); });
}

bool
Engine::loadFileAndPresetFromSysEx(const AUMIDIEvent& midiEvent) noexcept {
  os_log_info(log_, "loadFileAndPresetFromSysEx BEGIN");

  if (midiEvent.length < LoadPresetSysExPayload::minPayloadSize) {
    os_log_error(log_, "loadFileAndPresetFromSysEx END - invalid midi payload %d", midiEvent.length);
    return false;
  }

  const uint8_t* bytes = midiEvent.data;
  __block auto payload = std::vector<uint8_t>(bytes, bytes + midiEvent.length);

  dispatch_async(workQueue_, ^{ loadFileAndPreset(std::move(payload)); });

  return true;
}

void
Engine::loadFileAndPreset(std::vector<uint8_t>&& bytes) noexcept {
  auto payload = reinterpret_cast<const LoadPresetSysExPayload*>(bytes.data());
  auto presetIndex = payload->presetIndex;
  auto overrideCount = payload->overrideCount;
  auto pos1 = reinterpret_cast<const SF2::MIDI::GeneratorOverride*>(payload + 1);
  auto overrides = std::vector<MIDI::GeneratorOverride>(pos1, pos1 + overrideCount);
  auto pathStart = reinterpret_cast<const uint8_t*>(pos1 + overrideCount);
  auto pathCount = size_t((bytes.data() + bytes.size()) - pathStart) - 1;
  auto path = pathCount == 0 ? std::string("") : Utils::Base64::decode(pathStart, pathCount);

  if (!path.empty()) {
    load(path, presetIndex);
  } else {
    usePresetWithIndex(presetIndex);
  }

  os_log_info(log_, "loadFileAndPreset END");
}

bool
Engine::loadBookmarkAndPresetFromSysEx(const AUMIDIEvent& midiEvent) noexcept {
  os_log_info(log_, "loadBookmarkAndPresetFromSysEx BEGIN");

  if (midiEvent.length < LoadPresetSysExPayload::minPayloadSize) {
    os_log_error(log_, "loadBookmarkAndPresetFromSysEx END - invalid midi payload %d", midiEvent.length);
    return false;
  }

  const uint8_t* bytes = midiEvent.data;
  __block auto payload = std::vector<uint8_t>(bytes, bytes + midiEvent.length);

  dispatch_async(workQueue_, ^{ loadBookmarkAndPreset(std::move(payload)); });

  return true;
}

void
Engine::loadBookmarkAndPreset(std::vector<uint8_t>&& bytes) noexcept {
  auto payload = reinterpret_cast<const LoadPresetSysExPayload*>(bytes.data());
  auto presetIndex = payload->presetIndex;
  auto overrideCount = payload->overrideCount;
  auto pos1 = reinterpret_cast<const SF2::MIDI::GeneratorOverride*>(payload + 1);
  auto overrides = std::vector<MIDI::GeneratorOverride>(pos1, pos1 + overrideCount);
  auto dataStart = reinterpret_cast<const uint8_t*>(pos1 + overrideCount);
  auto dataCount = size_t((bytes.data() + bytes.size()) - dataStart) - 1;

  NSData* data = [NSData dataWithBytesNoCopy:(void*)dataStart length:dataCount freeWhenDone:false];
  NSData* bookmark = [data initWithBase64EncodedData:data options:0];

  __block NSError* error = nil;
  BOOL isStale = NO;
  NSURL* resolved = [NSURL URLByResolvingBookmarkData:bookmark
                                              options:0
                                        relativeToURL:nil
                                  bookmarkDataIsStale:&isStale
                                                error:&error];

  if (error != nil) {
    os_log_error(log_, "loadBookmarkAndPreset END - error from resolving bookmark data - %{public}@", error);
    return false;
  } else if (resolved == nil) {
    os_log_error(log_, "loadBookmarkAndPreset END - failed to resolve bookmark data (no error)");
    return false;
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
    NSError* error = nil;
    NSFileHandle* fileHandle = [NSFileHandle fileHandleForReadingFromURL:url error:&error];
    if (error != nil) {
      os_log_error(log_, "loadBookmarkAndPreset - failed to open file: %{public}@", error);
      return;
    }

    load(fileHandle.fileDescriptor, presetIndex);
  }];

  os_log_info(log_, "loadBookmarkAndPreset END");
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
Engine::changeProgram(uint8_t program) noexcept
{
  uint16_t msbBank = channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectMSB);
  uint16_t lsbBank = channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectLSB);
  uint16_t bank = msbBank * 128u + lsbBank;
  usePresetWithBankProgram(bank, program);
}

void
Engine::initialize(Float sampleRate) noexcept
{
  sampleRate_ = sampleRate;
  renderingTimeBudgetIntervalNanoseconds_ = 1.0 / sampleRate * 1.0e9;
  allOff();
  for (auto& voice : voices_) {
    voice.setSampleRate(sampleRate);
  }
  parameters_.reset();
}

void
Engine::stopAllExclusiveVoices(int exclusiveClass) noexcept
{
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    auto voiceIndex = *pos;
    if (voices_[voiceIndex].exclusiveClass() == exclusiveClass) {
      pos = stopVoice(voiceIndex);
    } else {
      ++pos;
    }
  }
}

void
Engine::stopSameKeyVoices(int eventKey) noexcept
{
  for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
    auto voiceIndex = *pos;
    if (voices_[voiceIndex].initiatingKey() == eventKey) {
      pos = stopVoice(voiceIndex);
    } else {
      ++pos;
    }
  }
}

void
Engine::startVoice(const Config& config) noexcept
{
  os_signpost_interval_begin(log_, startVoiceSignpost_, "startVoice");
  auto voiceIndex = oldestVoiceIndices_.voiceAcquire();
  os_log_info(log_, "startVoice - %lu", voiceIndex);
  voices_[voiceIndex].configure(config, channelState_);
  parameters_.applyChanged(voices_[voiceIndex].state());
  voices_[voiceIndex].start();
  updateActiveVoiceCount();
  os_signpost_interval_end(log_, startVoiceSignpost_, "startVoice");
}

OldestVoiceCollection<traits::maxVoiceCount>::iterator
Engine::stopVoice(size_t voiceIndex) noexcept
{
  os_signpost_interval_begin(log_, stopVoiceSignpost_, "stopVoice");
  os_log_info(log_, "stopVoice - %lu", voiceIndex);
  voices_[voiceIndex].stop();
  auto pos = oldestVoiceIndices_.voiceRelease(voiceIndex);
  os_signpost_interval_end(log_, stopVoiceSignpost_, "stopVoice");
  updateActiveVoiceCount();
  return pos;
}

void
Engine::updateActiveVoiceCount() noexcept
{
  auto value = oldestVoiceIndices_.active();
  os_log_info(log_, "updateActiveVoiceCount - %ld", value);
  [[parameterTree_ parameterWithAddress: valueOf(ParameterAddress::activeVoiceCount)] setValue: value];
}

void
Engine::updateDurationParameters() noexcept
{
  if constexpr (traits::renderDurationCollectionEnabled) {
    for (size_t voiceCount = 0; voiceCount < durationBuckets_.size(); ++voiceCount) {
      auto value = durationBuckets_[voiceCount];
      if (value > 0.0) {
        AUParameterAddress address = valueOf(ParameterAddress::lastParameterAddressPlusOne) + voiceCount;
        assert(address < valueOf(ParameterAddress::firstParameterAddress) + traits::engineParameterCount);
        [[parameterTree_ parameterWithAddress: address] setValue: value];
        durationBuckets_[voiceCount] = 0.0;
      }
    }
  }
}

void
Engine::bumpLastLoadFinished() noexcept
{
  os_log_info(log_, "bumpLastLoadFinished");
  auto param = [parameterTree_ parameterWithAddress: valueOf(ParameterAddress::lastLoadFinished)];
  lastLoadFinishedCounter_ += traits::lastLoadFinishedChange;
  [param setValue: AUValue(lastLoadFinishedCounter_)];
}

void
Engine::reset() noexcept
{
  allOff();
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
        value = portamentoRate();
        break;
      case ParameterAddress::oneVoicePerKeyModeEnabled:
        value = SF2::fromBool(oneVoicePerKeyModeEnabled());
        break;
      case ParameterAddress::polyphonicModeEnabled:
        value = SF2::fromBool(polyphonicModeEnabled());
        break;
      case ParameterAddress::activeVoiceCount:
        return oldestVoiceIndices_.active();
      case ParameterAddress::retriggerModeEnabled:
        value = SF2::fromBool(retriggerModeEnabled());
        break;
      case ParameterAddress::isRendering:
        return isRendering();
      case ParameterAddress::activeProgramIndex:
        value = activeProgramIndex();
        break;
      case ParameterAddress::activeBankIndex:
        value = activeBankIndex();
        break;
      case ParameterAddress::activePresetIndex:
        value = activePresetIndex();
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
  param.value = portamentoRate();
  [definitions addObject:param];

  flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_MeterReadOnly;

  // Report out various read-only states

  [definitions addObject: [AUParameterTree createParameterWithIdentifier:@"activeVoiceCount"
                                                                         name:@"activeVoiceCount"
                                                                      address:valueOf(ParameterAddress::activeVoiceCount)
                                                                          min:0
                                                                          max:voiceCountLimit()
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

  if constexpr (traits::renderDurationCollectionEnabled) {
    // Generate the buckets for render durations based on number of active voices
    for (size_t durationBucketIndex = 0; durationBucketIndex < durationBuckets_.size(); ++durationBucketIndex) {
      auto name = [NSString stringWithFormat:@"renderDuration%ld", durationBucketIndex];
      AUParameterAddress address = valueOf(ParameterAddress::lastParameterAddressPlusOne) + durationBucketIndex;
      [definitions addObject: [AUParameterTree createParameterWithIdentifier:name
                                                                        name:name
                                                                     address:address
                                                                         min:0.0
                                                                         max:10000.0
                                                                        unit:kAudioUnitParameterUnit_Milliseconds
                                                                    unitName:nullptr
                                                                       flags:flags
                                                                valueStrings:nullptr
                                                         dependentParameters:nullptr]];
    }
  }

  parameterTree_ = [AUParameterTree createTreeWithChildren:definitions];

  parameterTree_.implementorValueObserver = ^(AUParameter* parameter, AUValue value) {
    parameterValueChanged(parameter, value);
  };

  parameterTree_.implementorValueProvider = ^(AUParameter* parameter) {
    return provideParameterValue(parameter);
  };

  os_log_info(log_, "makeTree END");
}
