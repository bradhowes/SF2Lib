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

namespace SF2::IO { class File; }

namespace SF2::Render::Engine {

/**
 Engine that generates audio from SF2 files due to incoming MIDI signals. Maintains a collection of voices sized by the
 sole template parameter. A Voice generates samples based on the configuration it is given from a Preset.
 */
template <size_t VoiceCount>
class Engine : public DSPHeaders::EventProcessor<Engine<VoiceCount>> {
  using super = DSPHeaders::EventProcessor<Engine>;
  friend super;

public:
  static constexpr size_t maxVoiceCount = VoiceCount;
  using Config = Voice::State::Config;
  using Voice = Voice::Voice;

  /**
   Construct new engine and its voices.

   @param sampleRate the expected sample rate to use
   */
  Engine(Float sampleRate) : super(os_log_create("SoundFonts", "Engine")),
  sampleRate_{sampleRate}, oldestActive_{maxVoiceCount}
  {
    available_.reserve(maxVoiceCount);
    voices_.reserve(maxVoiceCount);
    for (size_t voiceIndex = 0; voiceIndex < maxVoiceCount; ++voiceIndex) {
      voices_.emplace_back(sampleRate, channelState_, voiceIndex);
      available_.push_back(voiceIndex);
    }
  }

  /**
   Update kernel and buffers to support the given format and channel count

   @param format the audio format to render
   @param maxFramesToRender the maximum number of samples we will be asked to render in one go
   */
  void setRenderingFormat(AVAudioFormat* format, AUAudioFrameCount maxFramesToRender) {
    super::setRenderingFormat(format, maxFramesToRender);
    initialize(format.channelCount, format.sampleRate);
//    for (auto& voice : voices_) {
//      voice.setMaxFramesToRender(maxFramesToRender);
//    }
  }

  /// Obtain the current sample rate
  Float sampleRate() const { return sampleRate_; }

  /// Obtain the MIDI channel assigned to the engine.
  const MIDI::ChannelState& channelState() const { return channelState_; }

  /**
   Load the presets from an SF2 file.

   @param file the file to load from
   */
  void load(const IO::File& file) {
    allOff();
    presets_.build(file);
  }

  /// @returns number of presets available.
  size_t presetCount() const { return presets_.size(); }

  /**
   Activate the preset at the given index.

   @param index the preset to use
   */
  void usePreset(size_t index) {
    if (index >= presets_.size()) throw std::runtime_error("invalid preset index");
    allOff();
    activePreset_ = index;
  }

  /// @return the number of active voices
  size_t activeVoiceCount() const { return oldestActive_.size(); }

  /**
   Turn off all voices, making them all available for rendering.
   */
  void allOff()
  {
    while (!oldestActive_.empty()) {
      auto voiceIndex = oldestActive_.takeOldest();
      std::cout << "voice " << voiceIndex << " available\n";
      available_.push_back(voiceIndex);
    }
  }

  /**
   Tell any voices playing the current MIDI key that the key has been released. The voice will continue to render until
   it figures out that it is done.

   @param key the MIDI key that was released
   */
  void noteOff(int key)
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
  void noteOn(int key, int velocity)
  {
    if (activePreset_ >= presets_.size()) return;
    for (const Config& config : presets_[activePreset_].find(key, velocity)) {
      startVoice(config);
    }
  }

  /**
   Render samples to the given stereo output buffers. The buffers are guaranteed to be able to hold `frameCount`
   samples, and `frameCount` will never be more than the `maxFramesToRender` value given to the `setRenderingFormat`.

   @param left pointer to buffer for left channel audio samples
   @param right pointer to buffer for right channel audio samples
   @param frameCount number of samples to render.
   */
  void render(AUValue* left, AUValue* right, AUAudioFrameCount frameCount)
  {
    std::fill(left, left + frameCount, 0.0);
    std::fill(right, right + frameCount, 0.0);
    for (auto voiceIndex : oldestActive_) {
      auto& voice{voices_[voiceIndex]};
      if (voice.isActive()) {
        voice.renderIntoByAdding(left, right, frameCount);
      }
      if (voice.isDone()) {
        oldestActive_.remove(voiceIndex);
        available_.push_back(voiceIndex);
      }
    }
  }

private:

  void initialize(int channelCount, double sampleRate) {
    sampleRate_ = sampleRate;
    allOff();
    for (auto& voice : voices_) {
      voice.setSampleRate(sampleRate);
    }
  }

  /// API for EventProcessor
  void setParameterFromEvent(const AUParameterEvent& event) {}

  /// API for EventProcessor
  void doMIDIEvent(const AUMIDIEvent& midiEvent)
  {
    if (midiEvent.eventType != AURenderEventMIDI || midiEvent.length < 1) return;
    switch (midiEvent.data[0] & 0xF0) {
      case MIDI::CoreEvent::noteOff:
        if (midiEvent.length == 2)
          noteOff(midiEvent.data[1]);
        break;
      case MIDI::CoreEvent::noteOn:
        if (midiEvent.length == 3)
          noteOn(midiEvent.data[1], midiEvent.data[2]);
        break;
      case MIDI::CoreEvent::keyPressure:
        if (midiEvent.length == 3)
          channelState_.setKeyPressure(midiEvent.data[1], midiEvent.data[2]);
        break;
      case MIDI::CoreEvent::controlChange:
        if (midiEvent.length == 3) {
          channelState_.setContinuousControllerValue(midiEvent.data[1], midiEvent.data[2]);
          nrpn_.process(midiEvent.data[1]);
        }
        break;
      case MIDI::CoreEvent::programChange:
        break;
      case MIDI::CoreEvent::channelPressure:
        if (midiEvent.length == 2)
          channelState_.setChannelPressure(midiEvent.data[1]);
        break;
      case MIDI::CoreEvent::pitchBend:
        if (midiEvent.length == 3) {
          int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
          channelState_.setPitchWheelValue(bend);
        }
        break;
      case MIDI::CoreEvent::reset:
        allOff();
        break;
    }
  }

  /// API for EventProcessor
  void doRendering(std::vector<AUValue*>& ins, std::vector<AUValue*>& outs, AUAudioFrameCount frameCount)
  {
    assert(outs.size() == 2);
    render(outs[0], outs[1], frameCount);
  }

  size_t selectVoice(const Config& config)
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
      found = oldestActive_.takeOldest();
    }

    return found;
  }

  void startVoice(const Config& config)
  {
    size_t index = selectVoice(config);
    if (index == voices_.size()) return;
    Voice& voice{voices_[index]};
    voice.configure(config);
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
};

} // end namespace SF2::Render