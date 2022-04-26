// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <vector>

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
   @param interpolator how to interpolate sample values
   */
  Voice(Float sampleRate, const MIDI::ChannelState& channelState, size_t voiceIndex,
        Sample::Generator::Interpolator interpolator = Sample::Generator::Interpolator::linear) noexcept;

  /**
   Set the sample rate to use for rendering.

   @param sampleRate the sample rate to use
   */
  void setSampleRate(Float sampleRate) noexcept { state_.setSampleRate(sampleRate); }

  /// @returns the unique index assigned to this voice instance.
  size_t voiceIndex() const noexcept { return voiceIndex_; }

  /// @returns the `exclusiveClass` generator value for the voice (only valid if voice is active).
  int exclusiveClass() const noexcept { return state_.unmodulated(Index::exclusiveClass); }

  /**
   Configure the voice for rendering.

   @param config the voice configuration to apply
   @param nrpn the MIDI NRPN values to apply
   */
  void configure(const State::Config& config, const MIDI::NRPN& nrpn) noexcept;

  /// @returns the MIDI key that started the voice. NOTE: not to be used for DSP processing.
  int initiatingKey() const noexcept { return state_.eventKey(); }

  /// @returns true if the key used to start the voice is still down.
  bool isKeyDown() const noexcept { return gainEnvelope_.isGated(); }

  /**
   Signal the envelopes that the key is no longer pressed, transitioning to release phase.
   */
  void releaseKey() noexcept {
    gainEnvelope_.gate(false);
    modulatorEnvelope_.gate(false);
  }

  /// @returns true if this voice is still rendering interesting samples
  bool isActive() const noexcept { return !isDone(); }

  /// @returns true if this voice is done processing and will no longer render meaningful samples.
  bool isDone() const noexcept {
    if (!done_) done_ = (!gainEnvelope_.isActive() || !sampleGenerator_.isActive());
    return done_;
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

   @returns next sample
   */
  Float renderSample() noexcept {
    if (isDone()) { return 0.0; }

    // Capture the current state of the modulators and envelopes.
    auto modLFO = modulatorLFO_.getNextValue();
    auto vibLFO = vibratoLFO_.getNextValue();
    auto modEnv = modulatorEnvelope_.getNextValue();
    auto volEnv = gainEnvelope_.getNextValue();

    // According to FluidSynth this is the right think to do.
    if (gainEnvelope_.isDelayed()) return 0.0;

    // Calculate the pitch to render and then generate a new sample.
    auto increment = pitch_.samplePhaseIncrement(modLFO, vibLFO, modEnv);
    auto sample = sampleGenerator_.generate(increment, canLoop());

    // Calculate the low-pass filter parameters. Only the frequency can be affected by an LFO or mod envelope, but both
    // can have external modulators attached to their primary state value.
    auto frequency = (state_.modulated(Index::initialFilterCutoff) +
                      state_.modulated(Index::modulatorLFOToFilterCutoff) * modLFO +
                      state_.modulated(Index::modulatorEnvelopeToFilterCutoff) * modEnv);
    auto resonance = state_.modulated(Index::initialFilterResonance);

    // Apply the filter on the sample.
    auto filtered = filter_.transform(frequency, resonance, sample);

    // Finally, calculate gain / attenuation to apply to filtered result and return attenuated value.
    auto gain = calculateGain(modLFO, volEnv);
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
      if (isDone()) break;
      Float pan = DSP::clamp(state_.modulated(Index::pan), -500, 500);
      Float leftPan, rightPan;
      DSP::panLookup(pan, leftPan, rightPan);
      SF2::Float sample{renderSample()};
      mixer.add(index, SF2::AUValue(leftPan * sample), SF2::AUValue(rightPan * sample), chorusSend, reverbSend);
    }
  }

  /// @returns `State` instance for the voice.
  State::State& state() { return state_; }

private:

  Float calculateGain(Float modLFO, Float volEnv) noexcept
  {
    // This formula follows what FluidSynth is doing for attenuation/gain.
    auto gain = (DSP::centibelsToAttenuation(state_.modulated(Index::initialAttenuation)) *
                 DSP::centibelsToAttenuation(DSP::MaximumAttenuationCentiBels * (1.0f - volEnv) +
                                             modLFO * -state_.modulated(Index::modulatorLFOToVolume)));

    // When in the release stage, look for a magical point at which one can no longer hear the sample being generated.
    // Use that as a short-circuit to flagging the voice as done.
    if (gainEnvelope_.stage() == Envelope::StageIndex::release) {
      auto minGain = sampleGenerator_.looped() ? noiseFloorOverMagnitudeOfLoop_ : noiseFloorOverMagnitude_;
      if (gain < minGain) {
        done_ = true;
      }
    }

    return gain;
  }

  State::State state_;
  LoopingMode loopingMode_;
  Sample::Pitch pitch_;
  Sample::Generator sampleGenerator_;
  Envelope::Generator gainEnvelope_;
  Envelope::Generator modulatorEnvelope_;
  LFO modulatorLFO_;
  LFO vibratoLFO_;
  LowPassFilter filter_;
  size_t voiceIndex_;
  Float noiseFloorOverMagnitude_;
  Float noiseFloorOverMagnitudeOfLoop_;

  mutable bool done_{false};
};

} // namespace SF2::Render::Voice
