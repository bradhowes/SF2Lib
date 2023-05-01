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
  super(), sampleRate_{sampleRate}, oldestActive_{voiceCount}, log_{os_log_create("SF2Lib", "Engine")}
  {
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
    initialize(format.channelCount, format.sampleRate);
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
    auto pos = oldestActive_.begin();
    while (pos != oldestActive_.end()) {
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
  }

  /**
   Activate one or more voices to play a MIDI key with the given velocity. NOTE: this is not thread-safe. When running
   in a render thread, one should use a MIDI command to start a note.

   @param key the MIDI key to play
   @param velocity the MIDI velocity to play at
   */
  void noteOn(int key, int velocity) noexcept
  {
    if (! hasActivePreset()) return;
    for (const Config& config : presets_[activePreset_].find(key, velocity)) {
      startVoice(config);
    }
  }

  /**
   Render samples to the given stereo output buffers. The buffers are guaranteed to be able to hold `frameCount`
   samples, and `frameCount` will never be more than the `maxFramesToRender` value given to the `setRenderingFormat`.

   @param mixer collection of buffers to render into
   @param frameCount number of samples to render.
   */
  void renderInto(Mixer mixer, AUAudioFrameCount frameCount) noexcept
  {
    auto pos = oldestActive_.begin();
    while (pos != oldestActive_.end()) {
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
  }

  MIDI::NRPN& nprn() { return nrpn_; }

private:

  void initialize(AVAudioChannelCount, double sampleRate) noexcept
  {
    sampleRate_ = sampleRate;
    allOff();
    for (auto& voice : voices_) {
      voice.setSampleRate(sampleRate);
    }
  }

  /// API for EventProcessor
  void setParameterFromEvent(const AUParameterEvent&) noexcept {}

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

  size_t selectVoice(int exclusiveClass) noexcept
  {
    size_t found = voices_.size();

    // If dealing with an exclusive voice, stop any that have the same `exclusiveClass` value.
    if (exclusiveClass > 0) {
      auto pos = oldestActive_.begin();
      while (pos != oldestActive_.end()) {
        auto voiceIndex = *pos;
        if (voices_[voiceIndex].exclusiveClass() == exclusiveClass) {
          pos = stopVoice(voiceIndex);
        } else {
          ++pos;
        }
      }
    }

    // Grab next available voice or steal the oldest voice that is active.
    if (!available_.empty()) {
      found = available_.back();
      available_.pop_back();
    } else {
      found = oldestActive_.takeOldest();
    }

    return found;
  }

  void startVoice(const Config& config) noexcept
  {
    auto voiceIndex = selectVoice(config.exclusiveClass());
    if (voiceIndex == voices_.size()) return;

    voices_[voiceIndex].start(config, nrpn_);
    oldestActive_.add(voiceIndex);
  }

  OldestActiveVoiceCache::iterator stopVoice(size_t voiceIndex) noexcept {
    voices_[voiceIndex].stop();
    auto pos = oldestActive_.remove(voiceIndex);
    available_.push_back(voiceIndex);
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
};

} // end namespace SF2::Render
