// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Engine/Mixer.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/LFO.hpp"
#include "SF2Lib/Render/LowPassFilter.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"
#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

/**
 Collection of types involved in generating audio samples for note that is being played. For a polyphonic instrument,
 there can be more than one voice playing at the same time.
 */
namespace SF2::Render::Voice {

/**
 A voice renders audio samples for a given note / pitch.
 */
class Voice
{
public:
  using Index = Entity::Generator::Index;

  /**
   These are values for the sampleModes (#54) generator.

   - none -- rendering does not loop
   - activeEnvelope -- loop as long as the envelope allows
   - duringKeyPress -- loop only while they key is down
   */
  enum struct LoopingMode {
    none = 0,
    activeEnvelope = 1,
    duringKeyPress = 3
  };

  /**
   Construct a new voice renderer.

   @param sampleRate the sample rate to use for generating audio
   @param channelState the MIDI state associated with the renderer
   @param voiceIndex the unique index assigned to this voice
   @param interpolator how to interpolate sample values
   */
  Voice(Float sampleRate, const MIDI::ChannelState& channelState, size_t voiceIndex,
        Sample::Generator::Interpolator interpolator = Sample::Generator::Interpolator::linear) noexcept;

  /// Allow move operations during construction to support std::vector
  Voice(Voice&&) noexcept = default;

  /// Disallow copy construction -- not needed
  Voice(const Voice&) = delete;

  /// Disallow copy assignment -- not needed
  Voice& operator=(const Voice&) noexcept = delete;

  /// Disallow move assignment -- not needed
  Voice& operator=(Voice&&) noexcept = delete;

  /// Ensure use of default destructor
  ~Voice() noexcept = default;
  // ~Voice() { std::cout << "~Voice " << voiceIndex_ << '\n'; };

  /**
   Set the sample rate to use for rendering.

   @param sampleRate the sample rate to use
   */
  void setSampleRate(Float sampleRate) noexcept {
    state_.setSampleRate(sampleRate);
    gainEnvelope_.setSampleRate(sampleRate);
    modulatorEnvelope_.setSampleRate(sampleRate);
    filter_.setSampleRate(sampleRate);
  }

  /// @returns the unique index assigned to this voice instance.
  size_t voiceIndex() const noexcept { return voiceIndex_; }

  /// @returns the `exclusiveClass` generator value for the voice (only valid if voice is active).
  int exclusiveClass() const noexcept { return state_.unmodulated(Index::exclusiveClass); }

  /**
   Start the voice rendering. At this point, `isKeyDown()` will return `true` until `releaseKey()` is called.

   @param config the voice configuration to apply
   */
  void start(const State::Config& config) noexcept;

  /**
   Stop the voice. After this, it will just produce 0.0 if rendered.
   */
  void stop() noexcept {
    os_log_debug(log_, "stop voice: %zu", voiceIndex_);
    active_ = false;
    gainEnvelope_.stop();
    sampleGenerator_.stop();
  }

  /// @returns true if this voice is still rendering interesting samples
  bool isActive() const noexcept { return active_; }

  /// @returns true if this voice is done processing and will no longer render meaningful samples.
  bool isDone() const noexcept { return !isActive(); }

  /// @returns the MIDI key that started the voice. NOTE: not to be used for DSP processing.
  int initiatingKey() const noexcept { return state_.eventKey(); }

  /// @returns true if the key used to start the voice is still down.
  bool isKeyDown() const noexcept { return keyDown_; }

  /**
   Signal the envelopes that the key is no longer pressed, transitioning to release phase. NOTE: this is invoked on a
   non-render thread so we need to signal the render thread that it has taken place and let the render thread handle it.
   */
  void releaseKey() noexcept {
    if (keyDown_) {
      keyDown_ = false;
      gainEnvelope_.gate(false);
      modulatorEnvelope_.gate(false);
    }
  }

  /// @returns looping mode of the sample being rendered
  LoopingMode loopingMode() const noexcept {
    switch (state_.unmodulated(Index::sampleModes)) {
      case 1: return LoopingMode::activeEnvelope;
      case 3: return LoopingMode::duringKeyPress;
      default: return LoopingMode::none;
    }
  }

  /// @returns true if the voice can enter a loop if it is available
  bool canLoop() const noexcept {
    return (loopingMode_ == LoopingMode::activeEnvelope && gainEnvelope_.isActive()) ||
    (loopingMode_ == LoopingMode::duringKeyPress && gainEnvelope_.isGated());
  }

  /**
   Renders the next sample for a voice. Inactive voices always return 0.0.

   Here are the modulation connections, taken from the SoundFont spec v2.

   ```
            Osc ------ Filter -- Amp -- L+R ----+-------------+-+-> Output
             | pitch     | Fc     | Volume      |            / /
            /|          /|        |             +- Reverb --+ /
   Mod Env +-----------+ |        |             |            /
            /|           |        |             +- Chorus --+
   Vib LFO + |           |        |
            /           /        /|
   Mod LFO +-----------+--------+ |
                                 /
   Vol Env ---------------------+
   ```

   @returns next sample
   */
  Float renderSample(bool debug = false) noexcept {
    if (!active_) {
      assert(!gainEnvelope_.isActive() && !sampleGenerator_.isActive());
      return 0.0;
    }

    // Capture the current state of the modulators and envelopes.
    auto modLFO = modulatorLFO_.getNextValue();
    auto vibLFO = vibratoLFO_.getNextValue();
    auto modEnv = modulatorEnvelope_.getNextValue();
    auto volEnv = gainEnvelope_.getNextValue();

    // According to FluidSynth this is the right thing to do.
    if (gainEnvelope_.isDelayed()) return 0.0;

    // Calculate the pitch to render and then generate a new sample.
    auto increment = pitch_.samplePhaseIncrement(modLFO, vibLFO, modEnv);
    auto sample = sampleGenerator_.generate(increment, canLoop());

    // Calculate the low-pass filter parameters. Only the frequency can be affected by an LFO or mod envelope, but both
    // can have external modulators attached to their primary state value.
    auto frequency = (state_.modulated(Index::initialFilterCutoff) +
                      state_.modulated(Index::modulatorLFOToFilterCutoff) * modLFO.val +
                      state_.modulated(Index::modulatorEnvelopeToFilterCutoff) * modEnv);
    auto resonance = state_.modulated(Index::initialFilterResonance);

    // Apply the filter on the sample.
    auto filtered = filter_.transform(frequency, resonance, sample);

    // Finally, calculate gain / attenuation to apply to filtered result and return attenuated value.
    auto gain = calculateGain(modLFO, volEnv);
    if (debug) {
      os_log_debug(log_, "renderSample modEnv: %f volEnv: %f gain: %f sample: %f", modEnv, volEnv, gain, sample);
    }

    if (!gainEnvelope_.isActive() || !sampleGenerator_.isActive()) stop();

    return filtered * gain;
  }

  /**
   Repeatedly invoke `renderSample` `frameCount` times.

   @param mixer collection of buffers to mix into
   @param frameCount number of samples to render
   */
  void renderInto(Engine::Mixer& mixer, SF2::AUAudioFrameCount frameCount) noexcept {
    SF2::AUAudioFrameCount index = 0;
    SF2::AUValue chorusSend = SF2::AUValue(DSP::tenthPercentageToNormalized(state_.modulated(Index::chorusEffectSend)));
    SF2::AUValue reverbSend = SF2::AUValue(DSP::tenthPercentageToNormalized(state_.modulated(Index::reverbEffectSend)));

    for (; index < frameCount; ++index) {
      Float sample = isDone() ? 0.0 : renderSample(false);
      Float pan = state_.modulated(Index::pan);
      Float leftPan, rightPan;
      DSP::panLookup(pan, leftPan, rightPan);
      mixer.add(index, SF2::AUValue(leftPan * sample), SF2::AUValue(rightPan * sample), chorusSend, reverbSend);
    }
  }

  /// @returns `State` instance for the voice.
  State::State& state() noexcept { return state_; }

private:

  Float calculateGain(ModLFO::Value modLFO, Float volEnv) noexcept
  {
    // This formula follows what FluidSynth is doing for attenuation/gain.
    auto gain = (DSP::centibelsToAttenuation(state_.modulated(Index::initialAttenuation)) *
                 DSP::centibelsToAttenuation(DSP::MaximumAttenuationCentiBels * (1.0f - volEnv) +
                                             modLFO.val * -state_.modulated(Index::modulatorLFOToVolume)));

    // When in the release stage, look for a magical point at which one can no longer hear the sample being generated.
    // Use that as a short-circuit to flagging the voice as done.
    // FIXME: this is busted, sporadically returning very large values.
//    if (gainEnvelope_.activeIndex() == Envelope::StageIndex::release) {
//      auto minGain = sampleGenerator_.looped() ? noiseFloorOverMagnitudeOfLoop_ : noiseFloorOverMagnitude_;
//      if (gain < minGain) {
//        os_log_debug(log_, "calculateGain modLFO: %f volEnv: %f minGain: %f gain: %f",
//                     modLFO.val, volEnv, minGain, gain);
//        stop();
//      }
//    }

    return gain;
  }

  State::State state_;
  LoopingMode loopingMode_;
  Sample::Pitch pitch_;
  Sample::Generator sampleGenerator_;
  Envelope::Generator gainEnvelope_;
  Envelope::Generator modulatorEnvelope_;
  ModLFO modulatorLFO_;
  VibLFO vibratoLFO_;
  LowPassFilter filter_;
  Float noiseFloorOverMagnitude_;
  Float noiseFloorOverMagnitudeOfLoop_;

  bool active_{false};
  bool keyDown_{false};

  const size_t voiceIndex_;
  const os_log_t log_{os_log_create("SF2Lib", "Voice")};
  const os_signpost_id_t startSignpost_{os_signpost_id_generate(log_)};
};

} // namespace SF2::Render::Voice
