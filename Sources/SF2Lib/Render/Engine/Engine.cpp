// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Utils/Base64.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/IO/File.hpp"

using namespace SF2::Render::Engine;

Engine::Engine(Float sampleRate, size_t voiceCount, Interpolator interpolator,
               size_t minimumNoteDurationMilliseconds) noexcept : super(),
sampleRate_{sampleRate},
minimumNoteDurationMilliseconds_{minimumNoteDurationMilliseconds},
parameters_{*this},
oldestActive_{voiceCount},
log_{os_log_create("SF2Lib", "Engine")},
renderSignpost_{os_signpost_id_generate(log_)},
noteOnSignpost_{os_signpost_id_generate(log_)},
noteOffSignpost_{os_signpost_id_generate(log_)},
startVoiceSignpost_{os_signpost_id_generate(log_)},
stopVoiceSignpost_{os_signpost_id_generate(log_)}
{
  available_.reserve(voiceCount);
  voices_.reserve(voiceCount);
  for (size_t voiceIndex = 0; voiceIndex < voiceCount; ++voiceIndex) {
    voices_.emplace_back(sampleRate, channelState_, voiceIndex, interpolator);
    available_.push_back(voiceIndex);
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

SF2::IO::File::LoadResponse
Engine::load(const std::string& path, size_t index) noexcept
{
  allOff();
  auto file = std::make_unique<IO::File>(path);
  auto response = file->load();
  os_log_info(log_, "load - response %d", valueOf(response));
  if (response == IO::File::LoadResponse::ok) {
    file_.swap(file);
    presets_.build(*file_);
    os_log_info(log_, "load - built %zu presets", presets_.size());
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
  allOff();
  auto index = presets_.locatePresetIndex(bank, program);
  if (index >= presets_.size()) {
    index = presets_.size();
  }
  activePreset_ = index;
  parameters_.reset();
}

void
Engine::allOff() noexcept
{
  while (!oldestActive_.empty()) {
    auto voiceIndex = oldestActive_.takeOldest();
    voices_[voiceIndex].stop();
    available_.push_back(voiceIndex);
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

  os_log_info(log_, "noteOn - number of voices: %lu", configs.size());
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

void
Engine::doParameterEvent(const AUParameterEvent& event) noexcept {
  // NOTE: this is running in the real-time render thread.
  os_log_debug(log_, "doParameterEvent - address: %llu value: %f", event.parameterAddress, event.value);
  auto rawIndex = event.parameterAddress;
  auto value = event.value;
  if (rawIndex < 0) return;
  if (rawIndex < valueOf(Entity::Generator::Index::numValues)) {
    auto index = Entity::Generator::Index(rawIndex);
    const auto& def = Entity::Generator::Definition::definition(index);
    parameters_.setLiveValue(index, def.clamp(int(std::round(value))));
    notifyParameterChanged(index);
  } else if (rawIndex >= valueOf(Parameters::EngineParameterAddress::portamentoModeEnabled) &&
             rawIndex < valueOf(Parameters::EngineParameterAddress::firstUnusedAddress)) {
    auto address = Parameters::EngineParameterAddress(rawIndex);
    switch (address) {
      case Parameters::EngineParameterAddress::portamentoModeEnabled:
        setPortamentoModeEnabled(SF2::toBool(value));
        return;
      case Parameters::EngineParameterAddress::portamentoRate:
        setPortamentoRate(size_t(value));
        return;
      case Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled:
        setOneVoicePerKeyModeEnabled(SF2::toBool(value));
        return;
      case Parameters::EngineParameterAddress::polyphonicModeEnabled:
        setPhonicMode(SF2::toBool(value) ? Engine::PhonicMode::poly : Engine::PhonicMode::mono);
        return;
      case Parameters::EngineParameterAddress::activeVoiceCount:
        return;
      case Parameters::EngineParameterAddress::retriggerModeEnabled:
        setRetriggerModeEnabled(SF2::toBool(value));
        return;
      case Parameters::EngineParameterAddress::firstUnusedAddress:
        return;
      default:
        return;
    }
  }
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
        os_log_info(log_, "doMIDIEvent - noteOff: %hhd", midiEvent.data[1]);
        noteOff(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::noteOn:
      if (midiEvent.length == 3) {
        os_log_info(log_, "doMIDIEvent - noteOn: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
        noteOn(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::keyPressure:
      if (midiEvent.length == 3) {
        os_log_info(log_, "doMIDIEvent - keyPressure: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
        channelState_.setNotePressure(midiEvent.data[1], midiEvent.data[2]);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::controlChange:
      if (midiEvent.length == 3) {
        os_log_info(log_, "doMIDIEvent - controlChange: %hhX %hhX", midiEvent.data[1], midiEvent.data[2]);
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
      if (midiEvent.length == 2) {
        os_log_info(log_, "doMIDIEvent - programChange: %hhd", midiEvent.data[1]);
        changeProgram(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::channelPressure:
      if (midiEvent.length == 2) {
        os_log_info(log_, "doMIDIEvent - channelPressure: %hhd", midiEvent.data[1]);
        channelState_.setChannelPressure(midiEvent.data[1]);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::pitchBend:
      if (midiEvent.length == 3) {
        os_log_info(log_, "doMIDIEvent - pitchBend: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
        int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
        channelState_.setPitchWheelValue(bend);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::systemExclusive:
      os_log_info(log_, "doMIDIEvent - systemExclusive: %hhX %hhX", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.data[1] == 0x7e && midiEvent.data[midiEvent.length - 1] == 0xF7) {
        switch (midiEvent.data[2]) {
          case 0x00:
            if (midiEvent.length >= 6) {
              loadFromMIDI(midiEvent);
            } else {
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
      os_log_info(log_, "doMIDIEvent - reset");
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
  os_log_info(log_, "processChannelMessage - %hhX %hhX", valueOf(channelMessage), value);
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
      os_log_debug(log_, "processControlChange - using sostenuto pedal");
      applySostenutoPedal();
    }
  } else {
    os_log_debug(log_, "processControlChange - releasing sostenuto pedal");
    doRelease = !currentPedalState.sostenutoPedalActive;
  }

  if (previousPedalState.sustainPedalActive && !currentPedalState.sustainPedalActive) {
    os_log_debug(log_, "processControlChange - releasing sustain pedal");
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

void
Engine::loadFromMIDI(const AUMIDIEvent& midiEvent) noexcept {
  const uint8_t* data = midiEvent.data;
  size_t index = data[3] * 128u + data[4];
  if (midiEvent.length > 6) {
    size_t count = midiEvent.length - 6;
    auto path = Utils::Base64::decode(data + 5, count);
    os_log_info(log_, "loadFromMIDI BEGIN - %{public}s index: %zu", path.c_str(), index);
    load(path, index);
  } else {
    usePresetWithIndex(index);
  }
}

std::vector<uint8_t>
Engine::createLoadFileUseIndex(const std::string& path, size_t preset) noexcept
{
  auto encoded = path.empty() ? "" : SF2::Utils::Base64::encode(path);
  auto nameOffset = 5;
  auto size = encoded.size() + size_t(nameOffset + 1);
  auto data = std::vector<uint8_t>(size, uint8_t(0));
  data[0] = SF2::valueOf(MIDI::CoreEvent::systemExclusive);
  data[1] = 0x7E; // Custom command for SF2Lib
  data[2] = 0x00; // unused subtype
  data[3] = static_cast<uint8_t>(preset / 128); // MSB of preset value
  data[4] = static_cast<uint8_t>(preset - data[3] * 128); // LSB of preset value
  std::copy_n(encoded.begin(), encoded.size(), data.begin() + nameOffset);
  data[size -1] = 0xF7;
  return data;
}

std::vector<uint8_t>
Engine::createUseIndex(size_t index) noexcept
{
  return createLoadFileUseIndex("", index);
}

std::vector<uint8_t>
Engine::createResetCommand() noexcept
{
  auto data = std::vector<uint8_t>(1, uint8_t(0));
  data[0] = SF2::valueOf(MIDI::CoreEvent::reset);
  return data;
}

std::vector<uint8_t>
Engine::createChannelMessage(MIDI::ControlChange channelMessage, uint8_t value) noexcept
{
  auto data = std::vector<uint8_t>(3, uint8_t(0));
  data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  data[1] = SF2::valueOf(channelMessage);
  data[2] = value;
  return data;
}

std::vector<std::vector<uint8_t>>
Engine::createUseBankProgram(uint16_t bank, uint8_t program) noexcept
{
  assert(bank < 128 * 128 && program < 128);
  auto commands = std::vector<std::vector<uint8_t>>();
  commands.reserve(3);

  auto bankMSB = uint8_t(bank / 128u);
  auto bankLSB = uint8_t(bank - bankMSB * 128u);
  auto data = std::vector<uint8_t>(3, uint8_t(0));
  data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  data[1] = SF2::valueOf(MIDI::ControlChange::bankSelectMSB);
  data[2] = bankMSB;
  commands.push_back(data);

  data = std::vector<uint8_t>(3, uint8_t(0));
  data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  data[1] = SF2::valueOf(MIDI::ControlChange::bankSelectLSB);
  data[2] = bankLSB;
  commands.push_back(data);

  data = std::vector<uint8_t>(2, uint8_t(0));
  data[0] = SF2::valueOf(MIDI::CoreEvent::programChange);
  data[1] = program;
  commands.push_back(data);

  return commands;
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
  for (auto pos = oldestActive_.begin(); pos != oldestActive_.end(); ) {
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
  for (auto pos = oldestActive_.begin(); pos != oldestActive_.end(); ) {
    auto voiceIndex = *pos;
    if (voices_[voiceIndex].initiatingKey() == eventKey) {
      pos = stopVoice(voiceIndex);
    } else {
      ++pos;
    }
  }
}

size_t
Engine::getVoice() noexcept
{
  size_t found = voices_.size();
  if (!available_.empty()) {
    found = available_.back();
    available_.pop_back();
  } else if (!oldestActive_.empty()) {
    found = oldestActive_.takeOldest();
  }

  return found;
}

void
Engine::startVoice(const Config& config) noexcept
{
  os_signpost_interval_begin(log_, startVoiceSignpost_, "startVoice", "");
  os_log_info(log_, "startVoice");
  auto voiceIndex = getVoice();
  if (voiceIndex != voices_.size()) {
    voices_[voiceIndex].configure(config);
    parameters_.applyChanged(voices_[voiceIndex].state());
    voices_[voiceIndex].start();
    oldestActive_.add(voiceIndex);
  }
  os_signpost_interval_end(log_, startVoiceSignpost_, "startVoice", "");
}

OldestActiveVoiceCache::iterator
Engine::stopVoice(size_t voiceIndex) noexcept
{
  os_signpost_interval_begin(log_, stopVoiceSignpost_, "stopVoice", "");
  voices_[voiceIndex].stop();
  auto pos = oldestActive_.remove(voiceIndex);
  available_.push_back(voiceIndex);
  os_signpost_interval_end(log_, stopVoiceSignpost_, "stopVoice", "");
  return pos;
}

void
Engine::reset() noexcept
{
  os_log_info(log_, "reset");
  allOff();
  channelState_.reset();
}
