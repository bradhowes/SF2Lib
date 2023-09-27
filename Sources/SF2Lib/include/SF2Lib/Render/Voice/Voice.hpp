// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>

#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Engine/Mixer.hpp"
#include "SF2Lib/Render/Envelope/Modulation.hpp"
#include "SF2Lib/Render/Envelope/Volume.hpp"
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
        Sample::Interpolator interpolator = Sample::Interpolator::linear) noexcept;

  /// Allow move operations during construction to support std::vector
  Voice(Voice&&) noexcept = default;

  ~Voice() noexcept = default;

  Voice(const Voice&) = delete;
  Voice& operator=(const Voice&) noexcept = delete;
  Voice& operator=(Voice&&) noexcept = delete;

  /**
   Set the sample rate to use for rendering.

   @param sampleRate the sample rate to use
   */
  void setSampleRate(Float sampleRate) noexcept {
    state_.setSampleRate(sampleRate);
    filter_.setSampleRate(sampleRate);
  }

  /// @returns the unique index assigned to this voice instance.
  size_t voiceIndex() const noexcept { return voiceIndex_; }

  /// @returns the `exclusiveClass` generator value for the voice (only valid if voice is active).
  int exclusiveClass() const noexcept { return state_.unmodulated(Index::exclusiveClass); }

  /**
   Configure the voice to begin rendering using the given settings.

   @param config the voice configuration to apply
   */
  void configure(const State::Config& config) noexcept;

  /**
   Start voice rendering. This initializes the envelopes and other internal state using the based on the configured
   generators set up in the `configure` call.
   */
  void start() noexcept;

  /**
   Stop the voice. After this, it will just produce 0.0 if asked to render a sample.
   */
  inline void stop() noexcept {
    active_ = false;
  }

  /// @returns true if this voice is still rendering interesting samples
  bool isActive() const noexcept { return active_; }

  /// @returns true if this voice has its key down
  bool isKeyDown() const noexcept { return keyDown_; }

  /// @returns true if this voice is done processing and will no longer render meaningful samples.
  bool isDone() const noexcept { return !isActive(); }

  /// @returns the MIDI key that started the voice. NOTE: not to be used for DSP processing.
  int initiatingKey() const noexcept { return state_.eventKey(); }

  /**
   Engine state that governs how a voice will react to a key release event.
   */
  struct ReleaseKeyState {
    size_t minimumNoteDurationSamples;
    MIDI::ChannelState::PedalState pedalState;
  };

  /**
   Signal the envelopes that the key is no longer pressed, transitioning to release phase. This is always the result of
   a MIDI event -- usually a note-off event, but pedal activity can also trigger it.

   @param releaseKeyState -- engine state that may affect if/when the key release actually takes place.
   */
  void releaseKey(const ReleaseKeyState& releaseKeyState) noexcept;

  /// @returns looping mode of the sample being rendered
  LoopingMode loopingMode() const noexcept;

  /// @returns true if the voice can enter a loop if it is available
  inline bool canLoop() const noexcept {
    return ((loopingMode_ == LoopingMode::activeEnvelope && volumeEnvelope_.isActive()) ||
            (loopingMode_ == LoopingMode::duringKeyPress && keyDown_));
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

   Note that in this routine, panning and effects are not performed.

   @returns next sample
   */
  inline Float renderSample() noexcept {
    if (! active_) { return 0_F; }

    // Capture the current state of the modulators and envelopes and advance them to the next sample.
    auto modLFO{modulatorLFO_.getNextValue()};
    auto vibLFO{vibratoLFO_.getNextValue()};
    auto modEnv{modulatorEnvelope_.getNextValue()};
    auto volEnv{volumeEnvelope_.getNextValue()};

    if (volumeEnvelope_.isDelayed()) return 0_F;

    // Calculate the pitch to render and then generate a new sample.
    //
    // NOTE: according the SF2 7.10, linked L/R voices should "be played entirely synchronously, with their pitch
    // controlled by the right sample's generators. All non-pitch generators should apply as normal". We do not do
    // this, and I'm not entirely sure how to do it given that modLFO and modEnv do not just affect pitch. It seems to
    // make sense to have common LFOs and envelopes for stereo voices.
    auto increment{pitch_.samplePhaseIncrement(modLFO, vibLFO, modEnv)};
    auto sample{sampleGenerator_.generate(increment, canLoop())};

    // Calculate gain / attenuation to apply to sample. Here we are deviating from FluidSynth: it treats the
    // attack stage of the volume envelope as special and just a linear ramp from 0.0 - 1.0. The other stages are
    // treated as a normalized representation of a dB attenuation.
    //
    // We instead do what I think is more intuitive and straightforward -- we always convert from normalized gain
    // of 0.0 - 1.0 to an attenuation in cB which is *then* converted along with the modLFO value into an attenuation
    // that is applied to the sample.
    auto volEnvCB{DSP::NoiseFloorCentiBels * (1_F - volEnv.val)};
    auto modLFOValCB{modLFO.val * -state_.modulated(Index::modulatorLFOToVolume)};
    auto gain{initialAttenuation_ * DSP::centibelsToAttenuation(modLFOValCB + volEnvCB)};

    // Calculate the low-pass filter parameters. Only the frequency can be affected by an LFO or mod envelope, but both
    // can have external modulators attached to their primary state value.
    auto frequency{(state_.modulated(Index::initialFilterCutoff) +
                    state_.modulated(Index::modulatorLFOToFilterCutoff) * modLFO.val +
                    state_.modulated(Index::modulatorEnvelopeToFilterCutoff) * modEnv.val)};
    auto resonance{state_.modulated(Index::initialFilterResonance)};
    auto filtered{filter_.transform(frequency, resonance, sample * gain)};

    ++sampleCounter_;

    if (!sampleGenerator_.isActive()) {
      stop();
      return filtered;
    }

    if (pendingRelease_) {
      if (pendingRelease_ < sampleCounter_) {
        pendingRelease_ = 0;
        keyDown_ = false;
        volumeEnvelope_.gate(false);
        modulatorEnvelope_.gate(false);
      }
    } else if ((volumeEnvelope_.isRelease() && gain < DSP::NoiseFloor) || !volumeEnvelope_.isActive()) {
      stop();
    }

     return filtered;
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
    for (; index < frameCount && active_; ++index) {
      Float sample{renderSample()};
      Float pan{state_.modulated(Index::pan)};
      Float leftPan, rightPan;
      DSP::panLookup(pan, leftPan, rightPan);
      mixer.add(index, SF2::AUValue(leftPan * sample), SF2::AUValue(rightPan * sample), chorusSend, reverbSend);
    }

    for (; index < frameCount; ++index) {
      mixer.add(index, 0_F, 0_F, chorusSend, reverbSend);
    }
  }

  /// @returns `State` instance for the voice.
  State::State& state() noexcept { return state_; }

  /// Notification to recalculate the mods for the voice due to a change in MIDI state.
  void channelStateChanged() noexcept { state_.updateStateMods(); }

  /// Flag the voice as being affected by the sostenuto pedal.
  void useSostenuto() noexcept { sostenutoActive_ = true; }

private:
  State::State state_;
  size_t sampleCounter_{0};
  size_t pendingRelease_{0};
  LoopingMode loopingMode_;
  Sample::Pitch pitch_;
  Sample::Generator sampleGenerator_;
  Envelope::Volume volumeEnvelope_;
  Envelope::Modulation modulatorEnvelope_;
  ModLFO modulatorLFO_;
  VibLFO vibratoLFO_;
  LowPassFilter filter_;
  Float initialAttenuation_{1_F};

  bool active_{false};
  bool keyDown_{false};
  bool postponedRelease_{false};
  bool sostenutoActive_{false};

  const size_t voiceIndex_;
  const os_log_t log_{os_log_create("SF2Lib", "Voice")};
  const os_signpost_id_t configSignpost_{os_signpost_id_generate(log_)};
  const os_signpost_id_t startSignpost_{os_signpost_id_generate(log_)};
};

} // namespace SF2::Render::Voice
