// Copyright © 2022 Brad Howes. All rights reserved.

#include <cstdint>
#include <vector>

#include "SF2Util/Base64.hpp"
#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2File/IO/File.hpp"

using namespace SF2::Render::Engine;

Engine::Engine(Float sampleRate, size_t voiceCount, Interpolator interpolator,
               size_t minimumNoteDurationMilliseconds) noexcept : super("Engine"),
sampleRate_{sampleRate},
minimumNoteDurationMilliseconds_{minimumNoteDurationMilliseconds},
parameters_{*this},
oldestVoiceIndices_{voiceCount},
log_{Log::create("Engine")},
renderSignpost_{os_signpost_id_generate(log_)},
noteOnSignpost_{os_signpost_id_generate(log_)},
noteOffSignpost_{os_signpost_id_generate(log_)},
startVoiceSignpost_{os_signpost_id_generate(log_)},
stopVoiceSignpost_{os_signpost_id_generate(log_)}
{
  assert(voiceCount <= maxVoiceCount);

  voices_.reserve(voiceCount);
  for (size_t voiceIndex = 0; voiceIndex < voiceCount; ++voiceIndex) {
    voices_.emplace_back(sampleRate, channelState_, voiceIndex, interpolator);
  }
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
  allOff();
  auto file = std::make_unique<IO::File>(path);
  auto response = file->load();
  if (response == IO::File::LoadResponse::ok) {
    file_.swap(file);
    presets_.build(*file_);
    usePresetWithIndex(index);
  }
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
  os_signpost_interval_begin(log_, noteOnSignpost_, "noteOn", "key: %d vel: %d", key, velocity);
  if (! hasActivePreset()) return;

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
  os_signpost_interval_end(log_, noteOnSignpost_, "noteOn", "key: %d vel: %d", key, velocity);
}

void
Engine::noteOff(int key) noexcept
{
  os_signpost_interval_begin(log_, noteOffSignpost_, "noteOff", "key: %d", key);
  visitActiveVoice([=](Voice& voice, const Voice::ReleaseKeyState& releaseKeyState) {
    if (voice.initiatingKey() == key) {
      voice.releaseKey(releaseKeyState);
    }
  });
  os_signpost_interval_end(log_, noteOffSignpost_, "noteOff", "key: %d", key);
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
  } else if (rawIndex >= valueOf(Parameters::EngineParameterAddress::firstEngineParameterAddress) &&
             rawIndex < valueOf(Parameters::EngineParameterAddress::lastEngineParameterAddressPlusOne)) {
    auto address = Parameters::EngineParameterAddress(rawIndex);
    switch (address) {
      case Parameters::EngineParameterAddress::portamentoModeEnabled:
        setPortamentoModeEnabled(SF2::toBool(value));
        break;
      case Parameters::EngineParameterAddress::portamentoRate:
        setPortamentoRate(size_t(value));
        break;
      case Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled:
        setOneVoicePerKeyModeEnabled(SF2::toBool(value));
        break;
      case Parameters::EngineParameterAddress::polyphonicModeEnabled:
        setPhonicMode(SF2::toBool(value) ? Engine::PhonicMode::poly : Engine::PhonicMode::mono);
        break;
      case Parameters::EngineParameterAddress::activeVoiceCount:
        break;
      case Parameters::EngineParameterAddress::retriggerModeEnabled:
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
  if (midiEvent.length < 1) return;
  if (midiEvent.data[0] < 0x80) return;

  auto event = MIDI::CoreEvent(midiEvent.data[0] < 0xF0 ? (midiEvent.data[0] & 0xF0) : midiEvent.data[0]);
  switch (event) {
    case MIDI::CoreEvent::noteOff:
      if (midiEvent.length > 1) {
        noteOff(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::noteOn:
      if (midiEvent.length == 3) {
        noteOn(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::keyPressure:
      if (midiEvent.length == 3) {
        channelState_.setNotePressure(midiEvent.data[1], midiEvent.data[2]);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::controlChange:
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
      if (midiEvent.length >= 2) {
        changeProgram(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::channelPressure:
      if (midiEvent.length >= 2) {
        channelState_.setChannelPressure(midiEvent.data[1]);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::pitchBend:
      if (midiEvent.length == 3) {
        int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
        channelState_.setPitchWheelValue(bend);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::systemExclusive:
      if (midiEvent.data[1] == 0x7e && midiEvent.data[midiEvent.length - 1] == 0xF7) {
        switch (midiEvent.data[2]) {
          case 0x00:
            if (!loadFileAndPresetFromSysEx(midiEvent)) {
              os_log_debug(log_, "doMIDIEvent - systemExclusive ignored due to length < 6");
            }
            break;

          default:
            os_log_debug(log_, "doMIDIEvent - systemExclusive ignored");
            break;
        }
      }
      break;

    case MIDI::CoreEvent::reset:
      reset();
      break;

    default:
      os_log_debug(log_, "doMIDIEvent - ignored %hhX", midiEvent.data[0]);
      break;
  }
}

void
Engine::processChannelMessage(MIDI::ControlChange channelMessage, uint8_t value) noexcept
{
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
    parameters_.applyOne(voice.state(), index);
  });
}

void
Engine::notifyActiveVoicesChannelStateChanged() noexcept
{
  visitActiveVoice([](Voice& voice, const Voice::ReleaseKeyState&) { voice.channelStateChanged(); });
}

struct LoadPresetSysExPayload {
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
    payload->manufacturer = 0x7E;
    payload->model = 0x00;
    payload->presetIndex = presetIndex;
    payload->overrideCount = overrides.size();
    auto pos1 = reinterpret_cast<SF2::MIDI::GeneratorOverride*>((bytes.data() + sizeof(LoadPresetSysExPayload)));
    auto pos2 = std::copy(overrides.begin(), overrides.end(), pos1);
    auto pos3 = reinterpret_cast<uint8_t*>(std::copy(encodedFilePath.begin(), encodedFilePath.end(),
                                                     reinterpret_cast<char*>(pos2)));
    *pos3++ = 0xF7;

    assert(pos3 - bytes.data() == bytes.size());
    assert(bytes.size() >= minPayloadSize);

    return bytes;
  }
};

bool
Engine::loadFileAndPresetFromSysEx(const AUMIDIEvent& midiEvent) noexcept {
  if (midiEvent.length < LoadPresetSysExPayload::minPayloadSize) {
    return false;
  }

  const uint8_t* bytes = midiEvent.data;
  auto payload = reinterpret_cast<const LoadPresetSysExPayload*>(bytes);
  auto presetIndex = payload->presetIndex;
  auto overrideCount = payload->overrideCount;
  auto pos1 = reinterpret_cast<const SF2::MIDI::GeneratorOverride*>(payload + 1);
  auto overrides = std::vector<MIDI::GeneratorOverride>(pos1, pos1 + overrideCount);
  auto pathStart = reinterpret_cast<const uint8_t*>(pos1 + overrideCount);
  auto pathCount = (bytes + midiEvent.length) - pathStart - 1;
  auto path = pathCount == 0 ? std::string("") : Utils::Base64::decode(pathStart, pathCount);
  if (!path.empty()) {
    load(path, presetIndex);
  } else {
    usePresetWithIndex(presetIndex);
  }

  return true;
}

std::vector<uint8_t>
Engine::createLoadFileUsePresetPayload(const std::string& filePath, size_t presetIndex,
                                       const MIDI::GeneratorOverrideVector& overrides) noexcept
{
  return LoadPresetSysExPayload::make(overrides, filePath, presetIndex);
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
  os_signpost_interval_begin(log_, startVoiceSignpost_, "startVoice", "");
  auto voiceIndex = oldestVoiceIndices_.voiceAcquire();
  os_log_info(log_, "startVoice - %lu", voiceIndex);
  voices_[voiceIndex].configure(config);
  parameters_.applyChanged(voices_[voiceIndex].state());
  voices_[voiceIndex].start();
  os_signpost_interval_end(log_, startVoiceSignpost_, "startVoice", "");
}

OldestVoiceCollection<Engine::maxVoiceCount>::iterator
Engine::stopVoice(size_t voiceIndex) noexcept
{
  os_signpost_interval_begin(log_, stopVoiceSignpost_, "stopVoice", "");
  os_log_info(log_, "stopVoice - %lu", voiceIndex);
  voices_[voiceIndex].stop();
  auto pos = oldestVoiceIndices_.voiceRelease(voiceIndex);
  os_signpost_interval_end(log_, stopVoiceSignpost_, "stopVoice", "");
  return pos;
}

void
Engine::reset() noexcept
{
  allOff();
  channelState_.reset();
}
