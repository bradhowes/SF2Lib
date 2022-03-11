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
#include "SF2Lib/Render/Engine/OldestActiveVoiceCache.hpp"
#include "SF2Lib/Render/Engine/PresetCollection.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"
#include "SF2Lib/Utils/Mixer.hpp"

namespace SF2::IO { class File; }

namespace SF2::Render::Engine {

/**
 Engine that generates audio from SF2 files due to incoming MIDI signals. Maintains a collection of voices sized by the
 sole template parameter. A Voice generates samples based on the configuration it is given from a Preset.
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
  super(os_log_create("SoundFonts", "Engine")), sampleRate_{sampleRate}, oldestActive_{voiceCount}
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
  void setRenderingFormat(AVAudioFormat* format, AUAudioFrameCount maxFramesToRender) noexcept {
    super::setRenderingFormat(format, maxFramesToRender);
    initialize(format.channelCount, format.sampleRate);
    for (auto& voice : voices_) {
      voice.setMaxFramesToRender(maxFramesToRender);
    }
  }

  /// @returns the current sample rate
  Float sampleRate() const noexcept { return sampleRate_; }

  /// @returns the MIDI channel state assigned to the engine
  MIDI::ChannelState& channelState() noexcept { return channelState_; }

  /// @returns the MIDI channel state assigned to the engine
  const MIDI::ChannelState& channelState() const noexcept { return channelState_; }

  /// @returns true if there is an active preset
  bool hasActivePreset() const { return activePreset_ < presets_.size(); }

  /**
   Load the presets from an SF2 file and activate one.

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
   Activate the preset at the given index.

   @param index the preset to use
   */
  void usePreset(size_t index) {
    allOff();
    if (index >= presets_.size()) {
      os_log_error(log_, "preset index %zu is invalid", index);
      index = presets_.size();
    }
    activePreset_ = index;
  }

  /// @return the number of active voices
  size_t activeVoiceCount() const noexcept { return oldestActive_.size(); }

  /**
   Turn off all voices, making them all available for rendering.
   */
  void allOff() noexcept
  {
    while (!oldestActive_.empty()) {
      auto voiceIndex = oldestActive_.takeOldest();
      available_.push_back(voiceIndex);
    }
  }

  /**
   Tell any voices playing the current MIDI key that the key has been released. The voice will continue to render until
   it figures out that it is done.

   @param key the MIDI key that was released
   */
  void noteOff(int key) noexcept
  {
    for (auto voiceIndex : oldestActive_) {
      const auto& voice{voices_[voiceIndex]};
      if (!voice.isActive()) {
        oldestActive_.remove(voiceIndex);
        available_.push_back(voiceIndex);
      }
      else if (voices_[voiceIndex].initiatingKey() == key) {
        voices_[voiceIndex].releaseKey();
      }
    }
  }

  /**
   Activate one or more voices to play a MIDI key with the given velocity.

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
  void renderInto(Utils::Mixer& mixer, AUAudioFrameCount frameCount) noexcept
  {
    for (auto voiceIndex : oldestActive_) {
      auto& voice{voices_[voiceIndex]};
      if (voice.isActive()) {
        voice.renderInto(mixer, frameCount);
      }
      if (voice.isDone()) {
        oldestActive_.remove(voiceIndex);
        available_.push_back(voiceIndex);
      }
    }
    mixer.shift(frameCount);
  }

  MIDI::NRPN& nprn() { return nrpn_; }

private:

  void initialize(int channelCount, double sampleRate) noexcept
  {
    sampleRate_ = sampleRate;
    allOff();
    for (auto& voice : voices_) {
      voice.setSampleRate(sampleRate);
    }
  }

  /// API for EventProcessor
  void setParameterFromEvent(const AUParameterEvent& event) noexcept {}

  /// API for EventProcessor
  void doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept;

  AUAudioUnitStatus doPullInput(const AudioTimeStamp* timestamp, UInt32 frameCount, NSInteger inputBusNumber,
                              AURenderPullInputBlock pullInputBlock) {
    return pullInput(timestamp, frameCount, inputBusNumber, pullInputBlock);
  }

  /// API for EventProcessor
  void doRendering(NSInteger outputBusNumber, std::vector<AUValue*>&, std::vector<AUValue*>& outs, AUAudioFrameCount frameCount) noexcept
  {
    assert(outs.size() >= 2);

    Utils::OutputBufferPair dry{outs[0], outs[1], frameCount};
    Utils::OutputBufferPair chorusSend;
    if (outs.size() >= 4) chorusSend = {outs[2], outs[3], frameCount};

    Utils::OutputBufferPair reverbSend;
    if (outs.size() >= 6) reverbSend = {outs[4], outs[5], frameCount};

    Utils::Mixer mixer{dry, chorusSend, reverbSend};
    renderInto(mixer, frameCount);
  }

  size_t selectVoice(const Config& config) noexcept
  {
    size_t found = voices_.size();

    // If dealing with an exclusive voice, stop any that have the same `exclusiveClass` value.
    auto exclusiveClass = config.exclusiveClass();
    if (exclusiveClass > 0) {
      for (auto voiceIndex : oldestActive_) {
        if (voices_[voiceIndex].exclusiveClass() == exclusiveClass) {
          oldestActive_.remove(voiceIndex);
          available_.push_back(voiceIndex);
        }
      }
    }

    // Grab next available voice
    if (!available_.empty()) {
      found = available_.back();
      available_.pop_back();
    }
    // Or steal the oldest voice that is active
    else if (!oldestActive_.empty()){
      os_log_debug(log_, "stealing oldest active voice");
      found = oldestActive_.takeOldest();
    }

    return found;
  }

  void startVoice(const Config& config) noexcept
  {
    size_t index = selectVoice(config);
    if (index == voices_.size()) return;
    Voice& voice{voices_[index]};
    voice.configure(config, nrpn_);
    oldestActive_.add(index);
  }

  Float sampleRate_;
  MIDI::ChannelState channelState_{};
  MIDI::NRPN nrpn_{channelState_};

  std::vector<Voice> voices_{};
  std::vector<size_t> available_{};
  OldestActiveVoiceCache oldestActive_;

  PresetCollection presets_{};
  size_t activePreset_{0};

  inline static Logger log_{Logger::Make("Render", "Engine")};
};

} // end namespace SF2::Render
