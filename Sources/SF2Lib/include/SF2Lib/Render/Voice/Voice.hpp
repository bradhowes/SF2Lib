// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <limits>

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

  /// Value of `partner()` when the voice is not part of a stereo pair
  static constexpr size_t noPartner = std::numeric_limits<size_t>::max();

  /**
   Construct a new voice renderer.
   */
  Voice() = default;

  /**
   Initialize a voice renderer.

   @param voiceIndex the unique index assigned to this voice
   @param sampleRate the sample rate to use for generating audio
   */
  void initialize(size_t voiceIndex, Float sampleRate) noexcept;

  // `Pitch` holds a reference to this voice's `state_`, so a default move would leave it referring to the moved-from
  // voice. Voices live in the Engine's fixed array and must not be moved.
  Voice(Voice&&) = delete;
  Voice& operator=(Voice&&) = delete;

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
  void stop() noexcept {
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
    /// A note released before it has rendered this many samples is cancelled (a debounce). 0 disables the check.
    size_t minimumNoteDurationSamples;
    MIDI::ChannelState::PedalState pedalState;
  };

  /**
   Record that the key is no longer pressed. If a pedal is holding the voice (sustain, or sostenuto when this voice was
   held at the time the sostenuto pedal went down) the release is postponed until `pedalReleased` says otherwise.
   Otherwise the envelopes transition to their release phase.

   If the voice has rendered fewer than `releaseKeyState.minimumNoteDurationSamples` samples, the note is instead
   cancelled with a fast release (see `fastRelease`), whatever the pedals: very short notes are treated as unintended.

   @param releaseKeyState -- engine state that may affect if/when the key release actually takes place.
   */
  void releaseKey(const ReleaseKeyState& releaseKeyState) noexcept;

  /**
   Record that the key is no longer pressed due to another with the same exclusiveClass setting.
   */
  void releaseKeyViaExclusiveClass() noexcept;

  /**
   Terminate the voice quickly but without a click: both envelopes enter a short release
   (`Envelope::Generator::noteAbortReleaseDuration`) from their current values. Used for exclusiveClass (SF2.01 8.1.2
   #57) and to shed voices when rendering would exceed its time budget.
   */
  void fastRelease() noexcept;

  /// @returns true if `fastRelease` was called since the voice started
  bool isFastReleasing() const noexcept { return fastReleasing_; }

  /**
   Link this voice to the other half of a stereo pair (SF2.01 7.10). The right-sample voice is the pitch leader: the
   pair renders in lockstep (see `renderLinkedInto`) and both use the leader's pitch.

   @param partner the index of the other voice
   @param isPitchLeader true if this voice plays the right sample
   */
  void linkStereoPartner(size_t partner, bool isPitchLeader) noexcept {
    partner_ = partner;
    pitchLeader_ = isPitchLeader;
  }

  /// Forget the stereo partner, so the voice renders on its own with its own pitch.
  void unlinkStereoPartner() noexcept {
    partner_ = noPartner;
    pitchLeader_ = false;
  }

  /// @returns the index of the other voice of a stereo pair, or `noPartner`
  size_t partner() const noexcept { return partner_; }

  /// @returns true if this voice supplies the pitch for its stereo partner
  bool isPitchLeader() const noexcept { return partner_ != noPartner && pitchLeader_; }

  /// @returns the number of the last render slice this voice took part in (see `markRendered`)
  uint64_t renderedSlice() const noexcept { return renderedSlice_; }

  /// Record that the voice has been rendered in the given slice, so the engine does not render it twice.
  void markRendered(uint64_t slice) noexcept { renderedSlice_ = slice; }
  /**
   Notification that a sustain or sostenuto pedal was released. Voices whose release was postponed and that are no
   longer held by any pedal transition to their release phase. Voices whose key is still down are not affected.

   @param pedalState -- the pedal state after the change
   */
  void pedalReleased(const MIDI::ChannelState::PedalState& pedalState) noexcept;

  /// @returns looping mode of the sample being rendered
  LoopingMode loopingMode() const noexcept;

  /// @returns true if the voice can enter a loop if it is available
  bool canLoop() const noexcept {
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
  Float renderSample() noexcept { return renderSample(nullptr, nullptr); }

  /**
   Renders the next sample, optionally taking the pitch from elsewhere. This supports stereo pairs (SF2.01 7.10):
   "Both samples should be played entirely synchronously, with their pitch controlled by the right sample's
   generators. All non-pitch generators should apply as normal". The right-sample voice reports its phase increment
   through `incrementOut`, and the left-sample voice renders with it through `pitchIncrement`. Each voice still runs
   its own LFOs and envelopes, which also drive volume, filter and (via modulators) other non-pitch values.

   @param pitchIncrement if not null, the sample phase increment to use instead of this voice's own pitch
   @param incrementOut if not null, receives the phase increment used for this sample
   @returns next sample
   */
  Float renderSample(const Float* pitchIncrement, Float* incrementOut) noexcept {
    if (! active_) { return 0_F; }
    return renderSample(pitchIncrement, incrementOut, sliceControls());
  }

private:

  /**
   Values derived from generators that only change on MIDI or parameter events. `EventProcessor` handles those between
   render slices, so `renderFrames` computes these once per slice instead of once per sample.
   */
  struct SliceControls {
    Sample::Pitch::Controls pitch;
    /// The phase increment to use for every sample when `pitch.isConstant()`
    Float constantIncrement;
    /// Linear gain from `initialAttenuation`
    Float attenuation;
    /// Centibels of attenuation at full mod LFO swing (negated `modulatorLFOToVolume`)
    Float modLFOToVolume;
    Float filterCutoff;
    Float modLFOToFilterCutoff;
    Float modEnvToFilterCutoff;
    Float filterResonance;
    Float leftPan;
    Float rightPan;
    SF2::AUValue chorusSend;
    SF2::AUValue reverbSend;
  };

  /// @returns the values that stay the same until the next MIDI or parameter event.
  SliceControls sliceControls() const noexcept {
    SliceControls controls;
    controls.pitch = pitch_.controls();
    controls.constantIncrement = controls.pitch.isConstant() ? Sample::Pitch::constantPhaseIncrement(controls.pitch)
                                                             : 0_F;
    controls.attenuation = DSP::centibelsToAttenuation(state_.modulated(Index::initialAttenuation));
    controls.modLFOToVolume = -state_.modulatedInRange(Index::modulatorLFOToVolume);
    controls.filterCutoff = state_.modulated(Index::initialFilterCutoff);
    controls.modLFOToFilterCutoff = state_.modulatedInRange(Index::modulatorLFOToFilterCutoff);
    controls.modEnvToFilterCutoff = state_.modulatedInRange(Index::modulatorEnvelopeToFilterCutoff);
    controls.filterResonance = state_.modulated(Index::initialFilterResonance);
    DSP::panLookup(state_.modulated(Index::pan), controls.leftPan, controls.rightPan);
    controls.chorusSend = SF2::AUValue(DSP::tenthPercentageToNormalized(state_.modulated(Index::chorusEffectSend)));
    controls.reverbSend = SF2::AUValue(DSP::tenthPercentageToNormalized(state_.modulated(Index::reverbEffectSend)));
    return controls;
  }

  /// Render the next sample using values captured for the current render slice.
  Float renderSample(const Float* pitchIncrement, Float* incrementOut, const SliceControls& controls) noexcept {
    if (! active_) { return 0_F; }
    ++samplesRendered_;

    // Capture the current state of the modulators and envelopes and advance them to the next sample.
    auto modLFO{modulatorLFO_.getNextValue()};
    auto vibLFO{vibratoLFO_.getNextValue()};
    auto modEnv{modulatorEnvelope_.getNextValue()};
    auto volEnv{volumeEnvelope_.getNextValue()};

    // Calculate the pitch to render. This is done even while the volume envelope is in its delay stage, so that a
    // stereo partner always has an increment to follow.
    auto increment{pitchIncrement != nullptr ? *pitchIncrement
                   : controls.pitch.isConstant() ? controls.constantIncrement
                   : Sample::Pitch::phaseIncrement(controls.pitch, modLFO, vibLFO, modEnv)};
    if (incrementOut != nullptr) *incrementOut = increment;

    if (volumeEnvelope_.isDelayed()) return 0_F;

    // Generate a new sample.
    auto sample{sampleGenerator_.generate(increment, canLoop())};

    // Calculate gain / attenuation to apply to sample. Here we are deviating from FluidSynth: it treats the
    // attack stage of the volume envelope as special and just a linear ramp from 0.0 - 1.0. The other stages are
    // treated as a normalized representation of a dB attenuation.
    //
    // We instead always treat the envelope value as a normalized dB attenuation (see
    // `Envelope::volumeEnvelopeToCentibels`), convert it to cB, and then combine it with the modLFO value into an
    // attenuation that is applied to the sample.
    auto volEnvCB{Envelope::volumeEnvelopeToCentibels(volEnv.val)};
    auto modLFOValCB{modLFO.val * controls.modLFOToVolume};
    auto gain{controls.attenuation * DSP::centibelsToAttenuation(modLFOValCB + volEnvCB)};

    // Update the low-pass filter parameters every `LowPassFilter::updateInterval` samples. Only the frequency can be
    // affected by the mod LFO and mod envelope, and both are in cents so they add to the absolute-cents cutoff
    // (SF2.01 8.1.2 #8, #10, #11). Both can also have external modulators attached to their primary state value.
    if (filter_.needsUpdate()) {
      auto frequency{controls.filterCutoff +
                     controls.modLFOToFilterCutoff * modLFO.val +
                     controls.modEnvToFilterCutoff * modEnv.val};
      filter_.update(frequency, controls.filterResonance);
    }
    auto filtered{filter_.transform(sample * gain)};

    if (!sampleGenerator_.isActive() ||
        !volumeEnvelope_.isActive() ||
        (volumeEnvelope_.isRelease() && gain < 0.0001)) {
      stop();
    }

    return filtered;
  }

public:

  /**
   Render `frameCount` samples while ramping the output linearly down to 0, then stop the voice. This is the last-resort
   path when a render slice runs out of its time budget: it costs only `frameCount` samples (the caller keeps that
   small) and avoids the step that stopping a sounding voice outright would cause.

   @param mixer collection of buffers to mix into
   @param frameCount number of samples over which to fade out
   */
  void renderFadeOut(Engine::Mixer& mixer, SF2::AUAudioFrameCount frameCount) noexcept {
    renderFrames(nullptr, mixer, frameCount, true);
    stop();
  }

  /**
   Repeatedly invoke `renderSample` up to `frameCount` times, stopping early if the voice becomes inactive. The mixer
   only accumulates, so nothing is written for the frames after that.

   @param mixer collection of buffers to mix into
   @param frameCount number of samples to render
   */
  void renderInto(Engine::Mixer& mixer, SF2::AUAudioFrameCount frameCount) noexcept {
    renderFrames(nullptr, mixer, frameCount, false);
  }

  /**
   Render this voice (the right sample of a stereo pair) and its partner in lockstep, sample by sample, with the
   partner using this voice's pitch (SF2.01 7.10). If this voice stops part way, the partner continues with its own
   pitch.

   @param follower the voice playing the left sample
   @param mixer collection of buffers to mix into
   @param frameCount number of samples to render
   */
  void renderLinkedInto(Voice& follower, Engine::Mixer& mixer, SF2::AUAudioFrameCount frameCount) noexcept {
    renderFrames(&follower, mixer, frameCount, false);
  }

  /**
   Like `renderFadeOut`, for a stereo pair rendered in lockstep. Both voices are stopped afterwards.

   @param follower the voice playing the left sample
   @param mixer collection of buffers to mix into
   @param frameCount number of samples over which to fade out
   */
  void renderLinkedFadeOut(Voice& follower, Engine::Mixer& mixer, SF2::AUAudioFrameCount frameCount) noexcept {
    renderFrames(&follower, mixer, frameCount, true);
    stop();
    follower.stop();
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

  /// Mix one rendered sample into the output, panned and sent to the effects with the slice's values.
  static void mix(Engine::Mixer& mixer, SF2::AUAudioFrameCount index, Float sample,
                  const SliceControls& controls) noexcept {
    mixer.add(index, SF2::AUValue(controls.leftPan * sample), SF2::AUValue(controls.rightPan * sample),
              controls.chorusSend, controls.reverbSend);
  }

  /**
   Render up to `frameCount` samples of this voice and, if given, of a stereo partner that follows this voice's pitch.
   Rendering stops once neither voice is active.

   @param follower the stereo partner to render in lockstep, or nullptr
   @param mixer collection of buffers to mix into
   @param frameCount number of samples to render
   @param fadeOut if true, ramp the output linearly down to 0 over the frames
   */
  void renderFrames(Voice* follower, Engine::Mixer& mixer, SF2::AUAudioFrameCount frameCount, bool fadeOut) noexcept {
    // No MIDI or parameter event can arrive during a slice (`EventProcessor` splits rendering at event boundaries), so
    // the generator-derived values are fixed until the next call.
    auto leaderControls{sliceControls()};
    auto followerControls{follower != nullptr ? follower->sliceControls() : SliceControls{}};
    for (SF2::AUAudioFrameCount index = 0; index < frameCount; ++index) {
      bool leaderActive = active_;
      bool followerActive = follower != nullptr && follower->active_;
      if (!leaderActive && !followerActive) break;
      Float gain{fadeOut ? Float(frameCount - index - 1) / Float(frameCount) : Float(1)};
      Float increment{0_F};
      if (leaderActive) {
        mix(mixer, index, renderSample(nullptr, follower != nullptr ? &increment : nullptr, leaderControls) * gain,
            leaderControls);
      }
      if (followerActive) {
        // If the leader has stopped, the follower carries on with its own pitch.
        Float sample{follower->renderSample(leaderActive ? &increment : nullptr, nullptr, followerControls)};
        mix(mixer, index, sample * gain, followerControls);
      }
    }
  }

  State::State state_{};
  LoopingMode loopingMode_{LoopingMode::none};
  Sample::Pitch pitch_{state_};
  Sample::Generator sampleGenerator_{};
  Envelope::Volume volumeEnvelope_{};
  Envelope::Modulation modulatorEnvelope_{};
  ModLFO modulatorLFO_{};
  VibLFO vibratoLFO_{};
  LowPassFilter filter_{};
  bool active_{false};
  bool keyDown_{false};
  bool released_{false};
  bool postponedRelease_{false};
  bool sostenutoActive_{false};
  bool fastReleasing_{false};

  /// Samples rendered since `start`, for the minimum note duration check in `releaseKey`
  size_t samplesRendered_{0};

  size_t partner_{noPartner};
  bool pitchLeader_{false};
  uint64_t renderedSlice_{0};

  size_t voiceIndex_;
  const os_log_t log_{Log::create("Voice")};
  const os_signpost_id_t configSignpost_{os_signpost_id_generate(log_)};
  const os_signpost_id_t startSignpost_{os_signpost_id_generate(log_)};
};

} // namespace SF2::Render::Voice
