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
   */
  Voice() noexcept = default;

  /**
   Initialize a voice renderer.

   @param voiceIndex the unique index assigned to this voice
   @param sampleRate the sample rate to use for generating audio
   @param interpolator how to interpolate sample values
   */
  void initialize(size_t voiceIndex, Float sampleRate, Sample::Interpolator interpolator) noexcept;

  /// Allow move operations during construction to support std::vector
  Voice(Voice&&) noexcept = default;

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
  void configure(const State::Config& config, const MIDI::ChannelState& channelState) noexcept;

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

  /// @returns true if the MIDI key that started this voice is still physically held down
  bool isKeyDown() const noexcept { return keyDown_; }

  /// @returns true if the voice's key-up has been deferred because a sustain or sostenuto pedal is holding it
  bool isReleasePostponed() const noexcept { return postponedRelease_; }

  /// @returns true if the envelopes have been told that the note was released
  bool isReleased() const noexcept { return released_; }

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
   Record that the key is no longer pressed. If a pedal is holding the voice (sustain, or sostenuto when this voice was
   held at the time the sostenuto pedal went down) the release is postponed until `pedalReleased` says otherwise.
   Otherwise the envelopes transition to their release phase.

   @param releaseKeyState -- engine state that may affect if/when the key release actually takes place.
   */
  void releaseKey(const ReleaseKeyState& releaseKeyState) noexcept;

  /**
   Notification that a sustain or sostenuto pedal was released. Voices whose release was postponed and that are no
   longer held by any pedal transition to their release phase. Voices whose key is still down are not affected.

   @param pedalState -- the pedal state after the change
   */
  void pedalReleased(const MIDI::ChannelState::PedalState& pedalState) noexcept;

  /// @returns looping mode of the sample being rendered
  LoopingMode loopingMode() const noexcept;

  /// @returns true if the voice can enter a loop if it is available
  inline bool canLoop() const noexcept {
    return ((loopingMode_ == LoopingMode::activeEnvelope && volumeEnvelope_.isActive()) ||
            (loopingMode_ == LoopingMode::duringKeyPress && !released_));
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
    // We instead always treat the envelope value as a normalized dB attenuation (see
    // `Envelope::volumeEnvelopeToCentibels`), convert it to cB, and then combine it with the modLFO value into an
    // attenuation that is applied to the sample.
    auto volEnvCB{Envelope::volumeEnvelopeToCentibels(volEnv.val)};
    auto modLFOValCB{modLFO.val * -state_.modulated(Index::modulatorLFOToVolume)};
    auto gain{initialAttenuation_ * DSP::centibelsToAttenuation(modLFOValCB + volEnvCB)};

    // Update the low-pass filter parameters every `LowPassFilter::updateInterval` samples. Only the frequency can be
    // affected by the mod LFO and mod envelope, and both are in cents so they add to the absolute-cents cutoff
    // (SF2.01 8.1.2 #8, #10, #11). Both can also have external modulators attached to their primary state value.
    if (filter_.needsUpdate()) {
      auto frequency{state_.modulated(Index::initialFilterCutoff) +
                     state_.modulated(Index::modulatorLFOToFilterCutoff) * modLFO.val +
                     state_.modulated(Index::modulatorEnvelopeToFilterCutoff) * modEnv.val};
      filter_.update(frequency, state_.modulated(Index::initialFilterResonance));
    }
    auto filtered{filter_.transform(sample * gain)};

    if (!sampleGenerator_.isActive() ||
        !volumeEnvelope_.isActive() ||
        (volumeEnvelope_.isRelease() && gain < 0.0001)) {
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
  void channelStateChanged(const MIDI::ChannelState& channelState) noexcept { state_.updateStateMods(channelState); }

  /// Flag the voice as being affected by the sostenuto pedal.
  void useSostenuto() noexcept { sostenutoActive_ = true; }

private:

  /// @returns true if the given pedal state holds this voice after its key is released
  bool isHeldByPedal(const MIDI::ChannelState::PedalState& pedalState) const noexcept {
    return pedalState.sustainPedalActive || (pedalState.sostenutoPedalActive && sostenutoActive_);
  }

  /// Move the envelopes into their release phase.
  void releaseEnvelopes() noexcept;

  State::State state_{};
  LoopingMode loopingMode_{LoopingMode::none};
  Sample::Pitch pitch_{state_};
  Sample::Generator sampleGenerator_{};
  Envelope::Volume volumeEnvelope_{};
  Envelope::Modulation modulatorEnvelope_{};
  ModLFO modulatorLFO_{};
  VibLFO vibratoLFO_{};
  LowPassFilter filter_{};
  Float initialAttenuation_{1_F};

  bool active_{false};
  bool keyDown_{false};
  bool released_{false};
  bool postponedRelease_{false};
  bool sostenutoActive_{false};

  size_t voiceIndex_;
  const os_log_t log_{Log::create("Voice")};
  const os_signpost_id_t configSignpost_{os_signpost_id_generate(log_)};
  const os_signpost_id_t startSignpost_{os_signpost_id_generate(log_)};
};

} // namespace SF2::Render::Voice
