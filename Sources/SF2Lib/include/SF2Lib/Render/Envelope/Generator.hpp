// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

#include "DSPHeaders/Types.hpp"
#include "SF2Util/DSP.hpp"
#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Envelope/Stage.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

/**
 Representation of an envelope with various stages that have their own timing characteristics and levels.

 The SF2 spec implies that the envelopes are to be thought of as representing an attenuation value
 where the peak is 0 dB attenuation and the floor is -100dB (regardless of bit count of the samples).
 This implementation instead treats the envelope as a value from 0.0 (floor) to 1.0 (peak).
 */
namespace SF2::Render::Envelope {

/// Stages defined in the SF2 2.01 spec (except for the `idle` state -- there is no Stage entity for it).
enum struct StageIndex : size_t {
  delay = 0,
  attack,
  hold,
  decay,
  sustain,
  release,
  idle,
  numStages = idle
};

/**
 The volume envelope value is a normalized representation of attenuation that is linear in decibels: 1.0 is the peak
 (0 cB of attenuation) and 0.0 is the noise floor (`DSP::NoiseFloorCentiBels` of attenuation). Stage increments are
 therefore constant dB changes per sample, which is what the spec asks for in the decay and release phases (8.1.2
 decayVolEnv / releaseVolEnv). These two functions are the *only* place where that mapping is defined; both the
 envelope configuration (sustain level) and the voice gain calculation must use them.

 @param value normalized volume envelope value in [0.0, 1.0]
 @returns attenuation in centibels in [0, NoiseFloorCentiBels]
 */
constexpr Float volumeEnvelopeToCentibels(Float value) noexcept {
  return SF2::DSP::NoiseFloorCentiBels * (1_F - std::clamp<Float>(value, 0_F, 1_F));
}

/**
 Inverse of `volumeEnvelopeToCentibels`. Values at or beyond the noise floor map to 0.0; negative values map to 1.0
 (spec 8.1.2 sustainVolEnv: "Values less than zero are to be interpreted as zero").

 @param centibels attenuation in centibels
 @returns normalized volume envelope value in [0.0, 1.0]
 */
constexpr Float centibelsToVolumeEnvelope(Float centibels) noexcept {
  return 1_F - std::clamp<Float>(centibels, 0_F, SF2::DSP::NoiseFloorCentiBels) / SF2::DSP::NoiseFloorCentiBels;
}

/**
 Shape of the volume envelope attack (SF2.01 8.1.2 #34 attackVolEnv): "the attack is 'convex'; the curve is nominally
 such that when applied to the decibel volume parameter, the result is linear in amplitude." Given the linear progress
 through the attack (0 to 1), return the normalised-dB envelope value whose gain (see `volumeEnvelopeToCentibels`) is
 that same fraction of full scale.

 @param progress how far through the attack, from 0 (start) to 1 (peak)
 @returns envelope value in the normalised-dB domain
 */
inline Float volumeEnvelopeAttackCurve(Float progress) noexcept {
  if (progress <= 0_F) return 0_F;
  if (progress >= 1_F) return 1_F;
  return centibelsToVolumeEnvelope(Float(-200.0 * std::log10(double(progress))));
}

/**
 Generator of values for the SF2 volume/modulation envelopes. An SF2 envelope contains 6 stages:

 - Delay -- number of samples to delay the beginning of the attack stage
 - Attack -- number of samples to ramp up from 0.0 to 1.0 in a exponential way
 - Hold -- number of samples to hold the envelope at 1.0 before entering the decay stage.
 - Decay -- number of samples to lower the envelope from 1.0 to the sustain level in a linear descent
 - Sustain -- a stage that lasts as long as a note is held down
 - Release -- number of samples to go from sustain level to ~0 in a linear descent

 The envelope will remain in the idle state until `gate(true)` is invoked. It will remain in the sustain stage until
 `gate(false)` is invoked at which point it will enter the `release` stage. Although the stages above are listed in the
 order in which they are performed, any stage will transition to the `release` stage upon a `gate(false)`
 call. Note that the envelope value is only changed by increments found in the Stage instances, and there is no forced
 adjustment of the value when transitioning from stage to stage. For instance, for an envelope value to traverse the
 entire delay, attack, hold, decay, sustain collection of stages, the generator gate must be `true` for all of the
 sample counts found in each stage up until the sustain stage (which effectively holds an unlimited sample count value).
 When the gate becomes `false` due to a key release, the envelope enters the release stage and the value begins to
 become smaller as it approaches 0.0. However, if the generator gate becomes `false` before the envelope enters the
 `sustain` stage, it could be at a level higher than the configured sustain level when it reaches the `release` stage.
 The decrement of the release stage is the (negative) slope of the line going from 1.0 to 0.0 over the duration of the
 release stage, so the envelope will have the same trailing edge slope regardless of what value the envelope has
 reached before entering the `release` stage.

 This behavior should also protect the rendering engine from discontinuities that might result when manually setting
 the envelope value to a fixed value when changing states.

 The more traditional ADSR (attack, decay, sustain, release) envelope can be achieved by setting the delay and hold
 durations to zero.
 */
class Generator {
  /// Collection of Stage entities that define the duration of part of the envelope.
  using StageArray = std::array<Stage, DSPHeaders::valueOf(StageIndex::numStages)>;
  /// Stage names for logging.  NOTE: extra name is due to 'idle' state that does not have a Stage entity.
  using StateNameArray = DSPHeaders::EnumIndexableValueArray<const char*, StageIndex, DSPHeaders::valueOf(StageIndex::numStages) + 1>;

  /**
   Collection of states for all of the stages in an SF2 envelope. Provides for indexing by StageIndex values.
   */
  struct Stages : public StageArray {
    using super = StageArray;

    Stages() : StageArray({Stage(), Stage(), Stage(), Stage(), Stage(), Stage()}) {}

    Stage& operator[](const StageIndex& index) { return super::operator[](DSPHeaders::valueOf(index)); }
    const Stage& operator[](const StageIndex& index) const { return super::operator[](DSPHeaders::valueOf(index)); }
  };

public:
  using Index = Entity::Generator::Index;
  using State = Render::Voice::State::State;

  static constexpr Float noteAbortReleaseDuration = 0.005; // 5ms

  /**
   Note has been released, so jump to the release stage.
   */
  void noteReleased() noexcept;

  /**
   Note was cut off by another note with the same exclusiveClass (SF2.01 8.1.2 #57). Enter a short release of
   `noteAbortReleaseDuration` from the current value, even if the envelope is already releasing.
   */
  void noteAborted() noexcept;

  /**
   Start the envelope generator. NOTE: this is already called by the configure...Envelope() routines below. Harmless to call again
   but there is no need. Unprotected for testing purposes.
   */
  void start() noexcept;

  /**
   Stop the envelope generator. All future requests for its value will report 0.0.

   @returns 0.0
   */
  Float stop() noexcept;

  /// @returns current stage index
  StageIndex activeIndex() const { return stageIndex_; }

  /// @returns true if the generator still has values to emit
  bool isActive() const noexcept { return stageIndex_ != StageIndex::idle; }

  /// @returns true if the generator is active and has not yet reached the release state
  bool isGated() const noexcept { return isActive() && stageIndex_ != StageIndex::release; }

  /// @returns true if in the delayed stage
  bool isDelayed() const noexcept { return stageIndex_ == StageIndex::delay; }

  /// @returns true if in the attack stage
  bool isAttack() const noexcept { return stageIndex_ == StageIndex::attack; }

  /// @returns true if in the release stage
  bool isRelease() const noexcept { return stageIndex_ == StageIndex::release; }

  /// @returns number of samples remaining in the current state
  int counter() const noexcept { return counter_; }

  /// @returns stage at given index
  const Stage& stage(StageIndex index) const noexcept { return stages_[index]; }

protected:
  /**
   Construct a NULL generator, one that will never emit any non-zero values. To be useful, a generator must be
   configured with a State that holds the stage definitions to use.
   */
  Generator(const char* logTag) noexcept;

  /// NOTE: only used for testing via EnvelopeTestInjector
  Generator(Float sampleRate, const char* logTag, Float delay, Float attack, Float hold, Float decay,
            int sustain, Float release) noexcept;

  /// @returns configured sustain level. NOTE: only used for testing
  Float sustainLevel() const noexcept { return sustainLevel_; }

  /// @returns the current envelope value.
  Float value() const noexcept { return value_; }

  /**
   Calculate the next envelope value. This must be called on every sample for proper timing of the stages.
   NOTE: part of render processing chain

   @returns the new envelope value.
   */
  Float getNextValue() noexcept {
    if (!checkForNextStage()) return 0_F;
    if (convexAttack_ && stageIndex_ == StageIndex::attack) {
      // The stage ramps the attack *progress* linearly; the envelope value follows the convex curve. Because `value_`
      // holds the shaped value, a release during the attack starts from the level actually being heard.
      attackProgress_ = std::min<Float>(stages_[StageIndex::attack].next(attackProgress_), 1_F);
      value_ = volumeEnvelopeAttackCurve(attackProgress_);
    } else {
      value_ = stages_[stageIndex_].next(value_);
    }
    if (value_ < 0_F) return stop();
    if (value_ > 1_F) value_ = 1_F;
    --counter_;
    checkForNextStage();
    return value_;
  }

  void configureVolumeEnvelope(const State& state) noexcept;

  /// Shape the attack with `volumeEnvelopeAttackCurve` (volume envelope only). The modulation envelope keeps a linear
  /// attack: "linear in Hz" for gen 26 depends on the destination and depth, and FluidSynth also uses a linear ramp.
  void enableConvexAttack() noexcept { convexAttack_ = true; }

  void configureModulationEnvelope(const State& state) noexcept;

private:
  /**
   Enter a new stage.

   @param next the stage to enter
   */
  void enterStage(StageIndex next) noexcept {
    stageIndex_ = next;
    if (next != StageIndex::idle) {
      counter_ = stages_[stageIndex_].durationInSamples();
    }
  }

  /**
   Check if transition to the next stage is warranted.

   @returns true if the envelope is still active
   */
  bool checkForNextStage() noexcept {
    while (counter_ == 0) {
      switch (stageIndex_) {
        case StageIndex::delay:     enterStage(StageIndex::attack); continue;
        case StageIndex::attack:    enterStage(StageIndex::hold); continue;
        case StageIndex::hold:      enterStage(StageIndex::decay); continue;
        case StageIndex::decay:     enterStage(StageIndex::sustain); continue;
        case StageIndex::sustain:   enterStage(StageIndex::release); continue; // this will actually never happen
        case StageIndex::release:   stop(); return false;
        case StageIndex::idle:      return false;
      }
    }
    return true;
  }

  Stages stages_{};
  StageIndex stageIndex_{StageIndex::idle};
  int counter_{0};
  Float value_{0_F};
  Float attackProgress_{0_F};
  Float sustainLevel_{0_F};
  int noteAbortReleaseDurationInSamples_{0};
  bool convexAttack_{false};
  const os_log_t log_;

  static const StateNameArray stageNames_;
};

} // namespace SF2::Render::Envelope
