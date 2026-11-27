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
  bool canLoop() const noexcept { return canLoop(volumeEnvelope_.activeIndex()); }

  /// @returns true if the voice can enter a loop when the volume envelope is in the given stage
  bool canLoop(Envelope::StageIndex volStage) const noexcept {
    return ((loopingMode_ == LoopingMode::activeEnvelope && volStage != Envelope::StageIndex::idle) ||
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
    auto modEnv{modulatorEnvelope_.getNextValue()};
    auto volEnv{volumeEnvelope_.getNextValue()};
    GainCache gainCache{};
    return renderSample(pitchIncrement, incrementOut, sliceControls(),
                        {modEnv.val, volEnv.val, volumeEnvelope_.activeIndex()}, gainCache);
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

  /// The envelope values for one sample, and the volume envelope stage after producing it.
  struct EnvelopeSample {
    Float modEnv;
    Float volEnv;
    Envelope::StageIndex volStage;
  };

  /**
   The last gain computed from the volume envelope. When the mod LFO does not affect the volume, the gain depends only
   on the volume envelope value, which is unchanged for long stretches (delay, hold, sustain), so the conversion from
   centibels can be skipped while it stays the same.
   */
  struct GainCache {
    bool valid{false};
    Float volEnv{0_F};
    Float gain{0_F};
  };

  /**
   Render the next sample using values captured for the current render slice and envelope values already advanced for
   this sample. The caller must check `active_` first.
   */
  Float renderSample(const Float* pitchIncrement, Float* incrementOut, const SliceControls& controls,
                     const EnvelopeSample& envelopes, GainCache& gainCache) noexcept {
    ++samplesRendered_;

    // Capture the current state of the LFOs and advance them to the next sample.
    auto modLFO{modulatorLFO_.getNextValue()};
    auto vibLFO{vibratoLFO_.getNextValue()};
    Envelope::Modulation::Value modEnv{envelopes.modEnv};

    // Calculate the pitch to render. This is done even while the volume envelope is in its delay stage, so that a
    // stereo partner always has an increment to follow.
    auto increment{pitchIncrement != nullptr ? *pitchIncrement
                   : controls.pitch.isConstant() ? controls.constantIncrement
                   : Sample::Pitch::phaseIncrement(controls.pitch, modLFO, vibLFO, modEnv)};
    if (incrementOut != nullptr) *incrementOut = increment;

    if (envelopes.volStage == Envelope::StageIndex::delay) return 0_F;

    // Generate a new sample.
    auto sample{sampleGenerator_.generate(increment, canLoop(envelopes.volStage))};

    // Calculate gain / attenuation to apply to sample. Here we are deviating from FluidSynth: it treats the
    // attack stage of the volume envelope as special and just a linear ramp from 0.0 - 1.0. The other stages are
    // treated as a normalized representation of a dB attenuation.
    //
    // We instead always treat the envelope value as a normalized dB attenuation (see
    // `Envelope::volumeEnvelopeToCentibels`), convert it to cB, and then combine it with the modLFO value into an
    // attenuation that is applied to the sample.
    //
    // With no mod LFO to volume, `modLFOValCB` is +/-0 and adding it to the (non-negative) `volEnvCB` changes nothing,
    // so the gain is a function of the volume envelope value alone and can be reused while that value is unchanged.
    Float gain;
    if (controls.modLFOToVolume == 0_F && gainCache.valid && gainCache.volEnv == envelopes.volEnv) {
      gain = gainCache.gain;
    } else {
      auto volEnvCB{Envelope::volumeEnvelopeToCentibels(envelopes.volEnv)};
      auto modLFOValCB{modLFO.val * controls.modLFOToVolume};
      gain = controls.attenuation * DSP::centibelsToAttenuation(modLFOValCB + volEnvCB);
      if (controls.modLFOToVolume == 0_F) gainCache = {true, envelopes.volEnv, gain};
    }

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
        envelopes.volStage == Envelope::StageIndex::idle ||
        (envelopes.volStage == Envelope::StageIndex::release && gain < 0.0001)) {
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

  /// Number of frames rendered per stage in `renderFrames`
  static constexpr SF2::AUAudioFrameCount blockSize = Engine::Mixer::maxBlockSize;

  /**
   Render up to `count` samples of this voice into `out`, stopping early if the voice becomes inactive. This is the
   stateful part of rendering (envelopes, LFOs, sample interpolation and the filter all depend on the previous sample),
   so it runs one sample at a time.

   @param count the number of samples to render (at most `blockSize`)
   @param pitchIncrements if not null, the phase increments to use for the first `pitchIncrementCount` samples instead
   of this voice's own pitch
   @param pitchIncrementCount the number of valid entries in `pitchIncrements`
   @param incrementsOut if not null, receives the phase increment used for each sample
   @param controls the values captured for the current render slice
   @param out receives the samples
   @returns the number of samples rendered (less than `count` if the voice stopped)
   */
  SF2::AUAudioFrameCount renderBlock(SF2::AUAudioFrameCount count, const Float* pitchIncrements,
                                     SF2::AUAudioFrameCount pitchIncrementCount, Float* incrementsOut,
                                     const SliceControls& controls, Float* out) noexcept {
    if (!active_) return 0;

    // Advance both envelopes for the whole block first. If the voice stops part way, the values past that point are
    // unused, and the envelopes are configured afresh before the voice plays again.
    Float modEnv[blockSize];
    Float volEnv[blockSize];
    Envelope::StageIndex volStages[blockSize];
    modulatorEnvelope_.fillBlock(modEnv, count);
    volumeEnvelope_.fillBlock(volEnv, volStages, count);

    GainCache gainCache{};
    SF2::AUAudioFrameCount index = 0;
    for (; index < count && active_; ++index) {
      const Float* pitchIncrement = index < pitchIncrementCount ? pitchIncrements + index : nullptr;
      out[index] = renderSample(pitchIncrement, incrementsOut != nullptr ? incrementsOut + index : nullptr, controls,
                                {modEnv[index], volEnv[index], volStages[index]}, gainCache);
    }
    return index;
  }

  /**
   Render up to `frameCount` samples of this voice and, if given, of a stereo partner that follows this voice's pitch.
   Rendering stops once neither voice is active.

   The frames are processed in blocks of `blockSize`. For each block, each voice first renders its samples one at a time
   (`renderBlock`), then the optional fade, the pan, the sends and the accumulation into the output buses run as
   separate loops over the whole block (`Mixer::addBlock`), which the compiler can vectorize. The results are the same
   as rendering and mixing each sample in turn: the leader's rendering does not depend on the follower, and each output
   frame still receives the leader's sample before the follower's.

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
    Float leaderSamples[blockSize];
    Float followerSamples[blockSize];
    Float increments[blockSize];
    for (SF2::AUAudioFrameCount blockStart = 0; blockStart < frameCount; blockStart += blockSize) {
      auto count = std::min(blockSize, frameCount - blockStart);

      // The leader reports its increments only when there is a follower to use them. A voice that stops part way
      // stays stopped, so the follower uses the leader's pitch for exactly the frames the leader rendered, and its own
      // pitch after that.
      auto leaderCount = renderBlock(count, nullptr, 0, follower != nullptr ? increments : nullptr, leaderControls,
                                     leaderSamples);
      auto followerCount = SF2::AUAudioFrameCount(0);
      if (follower != nullptr) {
        followerCount = follower->renderBlock(count, increments, leaderCount, nullptr, followerControls,
                                              followerSamples);
      }

      if (fadeOut) {
        applyFade(leaderSamples, leaderCount, blockStart, frameCount);
        applyFade(followerSamples, followerCount, blockStart, frameCount);
      }
      if (leaderCount > 0) mix(mixer, blockStart, leaderSamples, leaderCount, leaderControls);
      if (followerCount > 0) mix(mixer, blockStart, followerSamples, followerCount, followerControls);

      if (leaderCount < count && followerCount < count) break;
    }
  }

  /// Scale `samples` by the linear fade-out gain of `renderFadeOut`, for frames starting at `blockStart` of `frameCount`.
  static void applyFade(Float* samples, SF2::AUAudioFrameCount count, SF2::AUAudioFrameCount blockStart,
                        SF2::AUAudioFrameCount frameCount) noexcept {
    for (SF2::AUAudioFrameCount index = 0; index < count; ++index) {
      Float gain{Float(frameCount - (blockStart + index) - 1) / Float(frameCount)};
      samples[index] *= gain;
    }
  }

  /// Mix a block of rendered samples into the output, panned and sent to the effects with the slice's values.
  static void mix(Engine::Mixer& mixer, SF2::AUAudioFrameCount start, const Float* samples,
                  SF2::AUAudioFrameCount count, const SliceControls& controls) noexcept {
    mixer.addBlock(start, samples, count, controls.leftPan, controls.rightPan, controls.chorusSend,
                   controls.reverbSend);
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
