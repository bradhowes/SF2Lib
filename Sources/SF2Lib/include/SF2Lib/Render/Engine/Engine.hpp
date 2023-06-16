// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <functional>
#include <map>
#include <memory>
#include <queue>
#include <set>
#include <vector>

#include "DSPHeaders/EventProcessor.hpp"

#include "SF2Lib/MIDI/NRPN.hpp"
#include "SF2Lib/Render/Engine/Mixer.hpp"
#include "SF2Lib/Render/Engine/OldestActiveVoiceCache.hpp"
#include "SF2Lib/Render/Engine/PresetCollection.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

namespace SF2::IO { class File; }

namespace SF2::Render::Engine {

/**
 Engine that generates audio from SF2 files due to incoming MIDI signals. Maintains a collection of voices created at
 construction time. A Voice generates samples based on the configuration it is given from a Preset.

 Note that a major design goal is to keep from allocating any memory while a render thread is running and generating
 samples. This also implies that all communications with the engine while rendering (eg MIDI events or real-time
 parameter changes should be done with care. For the AUv3 use-case, this is handled by the `EventProcessor` base class
 and the AUv3 API. MIDI events and parameter changes are scheduled using dedicated APIs and the render thread sees them
 during a render request.
 */
class Engine : public DSPHeaders::EventProcessor<Engine> {
  using super = DSPHeaders::EventProcessor<Engine>;
  friend super;

public:
  using Config = Voice::State::Config;
  using Voice = Voice::Voice;
  using Interpolator = Render::Voice::Sample::Generator::Interpolator;

  /**
   Construct new engine and its voices.

   @param sampleRate the expected sample rate to use
   @param voiceCount the maximum number of individual voices to support
   @param interpolator the type of interpolation to use when rendering samples
   */
  Engine(Float sampleRate, size_t voiceCount, Interpolator interpolator) noexcept :
  super(), sampleRate_{sampleRate}, oldestActive_{voiceCount}, log_{os_log_create("SF2Lib", "Engine")},
  renderSignpost_{os_signpost_id_generate(log_)},
  noteOnSignpost_{os_signpost_id_generate(log_)},
  noteOffSignpost_{os_signpost_id_generate(log_)},
  startVoiceSignpost_{os_signpost_id_generate(log_)},
  stopForExclusiveVoiceSignpost_{os_signpost_id_generate(log_)}
  {
    // Voice::State::GenValue::Allocator
    available_.reserve(voiceCount);
    voices_.reserve(voiceCount);
    for (size_t voiceIndex = 0; voiceIndex < voiceCount; ++voiceIndex) {
      voices_.emplace_back(sampleRate, channelState_, voiceIndex, interpolator);
      available_.push_back(voiceIndex);
    }
  }

  /// @returns maximum number of voices available for simultaneous rendering
  size_t voiceCount() const noexcept { return voices_.size(); }
  
  /**
   Update kernel and buffers to support the given format and channel count

   @param format the audio format to render
   @param maxFramesToRender the maximum number of samples we will be asked to render in one go
   */
  void setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender) noexcept {
    super::setRenderingFormat(busCount, format, maxFramesToRender);
    initialize(format.sampleRate);
  }

  /// @returns the current sample rate
  Float sampleRate() const noexcept { return sampleRate_; }

  /// @returns the MIDI channel state assigned to the engine
  MIDI::ChannelState& channelState() noexcept { return channelState_; }

  /// @returns the MIDI channel state assigned to the engine
  const MIDI::ChannelState& channelState() const noexcept { return channelState_; }

  /// @returns true if there is an active preset
  bool hasActivePreset() const { return activePreset_ < presets_.size(); }

  /// @returns name of the active preset or empty string if none is active
  std::string activePresetName() const noexcept { return hasActivePreset() ? presets_[activePreset_].name() : ""; }

  /**
   Load the presets from an SF2 file and activate one. NOTE: this is not thread-safe. When running in a render thread,
   one should use the special MIDI system-exclusive command to perform a load. See comment in `doMIDIEvent`.

   @param file the file to load from
   @param index the preset to make active
   */
  void load(const IO::File& file, size_t index) noexcept {
    allOff();
    presets_.build(file);
    usePreset(index);
  }

  /// @returns number of presets available.
  size_t presetCount() const noexcept { return presets_.size(); }

  /**
   Activate the preset at the given index. NOTE: this is not thread-safe. When running in a render thread, one should
   use the program controller change MIDI command to perform a preset change.

   @param index the preset to use
   */
  void usePreset(size_t index) {
    setBypass(true);
    allOff();
    if (index >= presets_.size()) {
      index = presets_.size();
    }
    activePreset_ = index;
    setBypass(false);
  }

  /**
   Activate the preset at the given bank/program. NOTE: this is not thread-safe. When running in a render thread,
   one should use the bank/program controller change MIDI commands to perform a preset change.

   @param bank the bank to use
   @param program the program in the bank to use
   */
  void usePreset(int bank, int program) {
    setBypass(true);
    allOff();
    auto index = presets_.locatePresetIndex(bank, program);
    if (index >= presets_.size()) {
      index = presets_.size();
    }
    activePreset_ = index;
    setBypass(false);
  }

  /// @return the number of active voices
  size_t activeVoiceCount() const noexcept { return oldestActive_.size(); }

  /**
   Turn off all voices, making them all available for rendering. NOTE: this is not thread-safe. When running in a
   render thread, one should use a MIDI command to stop all notes.
   */
  void allOff() noexcept
  {
    setBypass(true);
    while (!oldestActive_.empty()) {
      auto voiceIndex = oldestActive_.takeOldest();
      voices_[voiceIndex].stop();
      available_.push_back(voiceIndex);
    }
    setBypass(false);
  }

  /**
   Tell any voices playing the current MIDI key that the key has been released. The voice will continue to render until
   it figures out that it is done. NOTE: this is not thread-safe. When running in a render thread, one should use a
   MIDI command to stop a note.

   @param key the MIDI key that was released
   */
  void noteOff(int key) noexcept
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
          voices_[voiceIndex].releaseKey();
        }
        ++pos;
      }
    }
    os_signpost_interval_end(log_, noteOffSignpost_, "noteOff", "key: %d", key);
  }

  /**
   Activate one or more voices to play a MIDI key with the given velocity. NOTE: this is not thread-safe. When running
   in a render thread, one should use a MIDI command to start a note.

   @param key the MIDI key to play
   @param velocity the MIDI velocity to play at
   */
  void noteOn(int key, int velocity) noexcept
  {
    os_signpost_interval_begin(log_, noteOnSignpost_, "noteOn", "key: %d vel: %d", key, velocity);
    if (! hasActivePreset()) return;
    for (const Config& config : presets_[activePreset_].find(key, velocity)) {
      startVoice(config);
    }
    os_signpost_interval_end(log_, noteOnSignpost_, "noteOn", "key: %d vel: %d", key, velocity);
  }

  /**
   Render samples to the given stereo output buffers. The buffers are guaranteed to be able to hold `frameCount`
   samples, and `frameCount` will never be more than the `maxFramesToRender` value given to the `setRenderingFormat`.

   @param mixer collection of buffers to render into
   @param frameCount number of samples to render.
   */
  void renderInto(Mixer mixer, AUAudioFrameCount frameCount) noexcept
  {
    os_signpost_interval_begin(log_, renderSignpost_, "renderInto", "voices: %lu frameCount: %d",
                               oldestActive_.size(), frameCount);
    for (auto pos = oldestActive_.begin(); pos != oldestActive_.end(); ) {
      auto voiceIndex = *pos;
      auto& voice{voices_[voiceIndex]};
      if (voice.isActive()) {
        voice.renderInto(mixer, frameCount);
      }
      if (voice.isDone()) {
        pos = oldestActive_.remove(voiceIndex);
        available_.push_back(voiceIndex);
      } else {
        ++pos;
      }
    }
    os_signpost_interval_end(log_, renderSignpost_, "renderInto", "voices: %lu frameCount: %d",
                             oldestActive_.size(), frameCount);
  }

  MIDI::NRPN& nprn() { return nrpn_; }

private:

  void initialize(Float sampleRate) noexcept
  {
    sampleRate_ = sampleRate;
    allOff();
    for (auto& voice : voices_) {
      voice.setSampleRate(sampleRate);
    }
  }

  /// API for EventProcessor
  void setParameterFromEvent(const AUParameterEvent& event) noexcept {
    os_log_debug(log_, "setParameterEvent - address: %llu value: %f", event.parameterAddress, event.value);
  }

  /// API for EventProcessor
  void doRenderingStateChanged(bool state) noexcept { if (!state) allOff(); }

  /// API for EventProcessor
  void doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept;

  /// API for EventProcessor
  void doRendering(NSInteger outputBusNumber, DSPHeaders::BusBuffers, DSPHeaders::BusBuffers outs,
                   AUAudioFrameCount frameCount) noexcept
  {
    if (outputBusNumber == 0) {
      // All of the work is done when working with output bus 0. If wired correctly, busses 1 and 2 will
      // use the buffered values that were created here.
      renderInto(Mixer(outs, busBuffers(1), busBuffers(2)), frameCount);
    }
  }

  void stopAllExclusiveVoices(int exclusiveClass) noexcept
  {
    for (auto pos = oldestActive_.begin(); pos != oldestActive_.end(); ) {
      auto voiceIndex = *pos;
      if (voices_[voiceIndex].exclusiveClass() == exclusiveClass) {
        pos = stopForExclusiveVoice(voiceIndex);
      } else {
        ++pos;
      }
    }
  }

  size_t getVoice() noexcept
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

  void startVoice(const Config& config) noexcept
  {
    os_signpost_interval_begin(log_, startVoiceSignpost_, "startVoice");
    auto exclusiveClass{config.exclusiveClass()};
    if (exclusiveClass > 0) {
      stopAllExclusiveVoices(exclusiveClass);
    }

    auto voiceIndex = getVoice();
    if (voiceIndex != voices_.size()) {
      voices_[voiceIndex].start(config, nrpn_);
      oldestActive_.add(voiceIndex);
    }
    os_signpost_interval_end(log_, startVoiceSignpost_, "startVoice");
  }

  OldestActiveVoiceCache::iterator stopForExclusiveVoice(size_t voiceIndex) noexcept {
    os_signpost_interval_begin(log_, stopForExclusiveVoiceSignpost_, "stopForExclusiveVoice");
    voices_[voiceIndex].stop();
    auto pos = oldestActive_.remove(voiceIndex);
    available_.push_back(voiceIndex);
    os_signpost_interval_end(log_, stopForExclusiveVoiceSignpost_, "stopForExclusiveVoice");
    return pos;
  }

  void processControlChange(MIDI::ControlChange cc) noexcept;
  void changeProgram(int program) noexcept;
  void loadFromMIDI(const AUMIDIEvent& midiEvent) noexcept;

  Float sampleRate_;
  MIDI::ChannelState channelState_{};
  MIDI::NRPN nrpn_{channelState_};

  std::vector<Voice> voices_{};
  std::vector<size_t> available_{};
  OldestActiveVoiceCache oldestActive_;

  PresetCollection presets_{};
  size_t activePreset_{0};
  os_log_t log_;

  os_signpost_id_t renderSignpost_;
  os_signpost_id_t noteOnSignpost_;
  os_signpost_id_t noteOffSignpost_;
  os_signpost_id_t startVoiceSignpost_;
  os_signpost_id_t stopForExclusiveVoiceSignpost_;
};

} // end namespace SF2::Render
