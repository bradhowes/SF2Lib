// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Utils/Base64.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/IO/File.hpp"

using namespace SF2::Render::Engine;

Engine::Engine(Float sampleRate, size_t voiceCount, Interpolator interpolator,
               size_t minimumNoteDurationMilliseconds) noexcept : super(),
sampleRate_{sampleRate},
minimumNoteDurationMilliseconds_{minimumNoteDurationMilliseconds},
oldestActive_{voiceCount}, log_{os_log_create("SF2Lib", "Engine")},
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

void
Engine::load(const IO::File& file, size_t index) noexcept
{
  allOff();
  presets_.build(file);
  os_log_info(log_, "load - built %zu presets", presets_.size());
  usePreset(index);
}

void
Engine::usePreset(size_t index)
{
  setBypass(true);
  allOff();
  if (index >= presets_.size()) {
    // Special case to flag no preset being used.
    index = presets_.size();
  }
  activePreset_ = index;
  setBypass(false);
}

void
Engine::usePreset(uint16_t bank, uint16_t program)
{
  setBypass(true);
  allOff();
  auto index = presets_.locatePresetIndex(bank, program);
  if (index >= presets_.size()) {
    index = presets_.size();
  }
  activePreset_ = index;
  setBypass(false);
}

void
Engine::allOff() noexcept
{
  setBypass(true);
  while (!oldestActive_.empty()) {
    auto voiceIndex = oldestActive_.takeOldest();
    voices_[voiceIndex].stop();
    available_.push_back(voiceIndex);
  }
  setBypass(false);
}

void
Engine::noteOn(int key, int velocity) noexcept
{
  os_signpost_interval_begin(log_, noteOnSignpost_, "noteOn", "key: %d vel: %d", key, velocity);
  if (! hasActivePreset()) return;
  auto configs = presets_[activePreset_].find(key, velocity);

  // Stop any existing voice with the same exclusiveClass value.
  for (const Config& config : configs) {
    auto exclusiveClass{config.exclusiveClass()};
    if (exclusiveClass > 0) {
      stopAllExclusiveVoices(exclusiveClass);
    }
    // stopSameKeyVoices(config.eventKey());
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
  for (auto pos = oldestActive_.begin(); pos != oldestActive_.end(); ) {
    auto voiceIndex = *pos;
    const auto& voice{voices_[voiceIndex]};
    if (!voice.isActive()) {
      pos = oldestActive_.remove(voiceIndex);
      available_.push_back(voiceIndex);
    } else {
      if (voices_[voiceIndex].initiatingKey() == key) {
        voices_[voiceIndex].releaseKey(minimumNoteDurationSamples());
      }
      ++pos;
    }
  }
  os_signpost_interval_end(log_, noteOffSignpost_, "noteOff", "key: %d", key);
}

void
Engine::doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept
{
  if (midiEvent.length < 1) return;
  if (midiEvent.data[0] < 0x80) return;

  auto event = MIDI::CoreEvent(midiEvent.data[0] < 0xF0 ? (midiEvent.data[0] & 0xF0) : midiEvent.data[0]);
  switch (event) {
    case MIDI::CoreEvent::noteOff:
      os_log_info(log_, "doMIDIEvent - noteOff: %hhd", midiEvent.data[1]);
      if (midiEvent.length > 1) {
        noteOff(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::noteOn:
      os_log_info(log_, "doMIDIEvent - noteOn: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length == 3) {
        noteOn(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::keyPressure:
      os_log_info(log_, "doMIDIEvent - keyPressure: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length == 3) {
        channelState_.setNotePressure(midiEvent.data[1], midiEvent.data[2]);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::controlChange:
      os_log_info(log_, "doMIDIEvent - controlChange: %hhX %hhX", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length == 3 && midiEvent.data[1] <= 127 && midiEvent.data[2] <= 127) {
        if (channelState_.setContinuousControllerValue(MIDI::ControlChange(midiEvent.data[1]), midiEvent.data[2])) {
          notifyActiveVoicesChannelStateChanged();
        }
      }
      break;

    case MIDI::CoreEvent::programChange:
      os_log_info(log_, "doMIDIEvent - programChange: %hhd", midiEvent.data[1]);
      if (midiEvent.length == 2) {
        changeProgram(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::channelPressure:
      os_log_info(log_, "doMIDIEvent - channelPressure: %hhd", midiEvent.data[1]);
      if (midiEvent.length == 2) {
        channelState_.setChannelPressure(midiEvent.data[1]);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

    case MIDI::CoreEvent::pitchBend:
      os_log_info(log_, "doMIDIEvent - pitchBend: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length == 3) {
        int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
        channelState_.setPitchWheelValue(bend);
        notifyActiveVoicesChannelStateChanged();
      }
      break;

      // System-Exclusive command for loading URL in SF2Engine:
      //
      //   0 0xF0 - System Exclusive
      //   1 0x7E - non-realtime ID
      //   2 0x00 - unused subtype
      //   3 0xAA - MSB of the preset to load
      //   4 0xBB - LSB of the preset to load
      //   5 ...  - N Base-64 encoded URL bytes
      // 5+N 0xF7 - EOX
      //
    case MIDI::CoreEvent::systemExclusive:
      os_log_info(log_, "doMIDIEvent - systemExclusive: %hhX %hhX", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length > 5 && midiEvent.data[1] == 0x7e && midiEvent.data[2] == 0x00) {
        loadFromMIDI(midiEvent);
      }
      break;

    case MIDI::CoreEvent::reset:
      os_log_info(log_, "doMIDIEvent - reset");
      allOff();
      channelState_.reset();
      break;

    default:
      break;
  }
}

void
Engine::notifyActiveVoicesChannelStateChanged() noexcept
{
  for (auto pos = oldestActive_.begin(); pos != oldestActive_.end();) {
    auto& voice{voices_[*pos++]};
    voice.channelStateChanged();
  }
}

void
Engine::loadFromMIDI(const AUMIDIEvent& midiEvent) noexcept {
  size_t count = midiEvent.length - 5;
  if (count < 1) return;

  size_t index = (*(&midiEvent.data[0] + 3) * 128) + *(&midiEvent.data[0] + 4);
  auto path = Utils::Base64::decode(&midiEvent.data[0] + 5, count);
  os_log_info(log_, "loadFromMIDI BEGIN - %{public}s index: %zu", path.c_str(), index);
  SF2::IO::File file{path.c_str()};
  load(file, index);
}

void
Engine::changeProgram(uint16_t program) noexcept {
  uint16_t bank = static_cast<uint16_t>(channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectMSB))
  * 128u +
  static_cast<uint16_t>(channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectLSB));
  usePreset(bank, program);
}

void
Engine::initialize(Float sampleRate) noexcept
{
  sampleRate_ = sampleRate;
  allOff();
  for (auto& voice : voices_) {
    voice.setSampleRate(sampleRate);
  }
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
