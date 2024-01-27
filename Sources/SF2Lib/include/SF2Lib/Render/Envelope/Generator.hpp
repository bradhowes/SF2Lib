// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Envelope/Stage.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

/**
 Representation of an envelope with various stages that have their own timing characteristics and levels.

 The SF2 spec implies that the envelopes are to be thought of as representing an attenuation value
 where the peak is 0 dB attenuation and the floor is -100dB (regardless of bit count of the samples).
 This implementation instead treats the envelope as a value from 0.0 (floor) to 1.0 (peak).
 */
namespace SF2::Render::Envelope {

/// Stages defined in the SF2 2.01 spec (except for the `idle` state).
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

  /**
   Collection of states for all of the stages in an SF2 envelope. Provides for indexing by StageIndex values.
   */
  struct Stages : public std::array<Stage, SF2::valueOf(StageIndex::numStages)> {
    using super = std::array<Stage, SF2::valueOf(StageIndex::numStages)>;
    Stage& operator[](const StageIndex& index) { return super::operator[](SF2::valueOf(index)); }
    const Stage& operator[](const StageIndex& index) const { return super::operator[](SF2::valueOf(index)); }
  };

public:
  using Index = Entity::Generator::Index;
  using State = Render::Voice::State::State;

  /**
   Set the status of a note playing. When true, the envelope begins proper. When set to false, the envelope will
   jump to the release stage.
   */
  void gate(bool noteOn) noexcept;

  /**
   Stop the envelope generator. All future requests for its value will report 0.0.
   */
  void stop() noexcept;

  /// @returns current stage index
  StageIndex activeIndex() const { return stageIndex_; }

  /// @returns true if the generator still has values to emit
  inline bool isActive() const noexcept { return stageIndex_ != StageIndex::idle; }

  /// @returns true if the generator is active and has not yet reached the release state
  inline bool isGated() const noexcept { return isActive() && stageIndex_ != StageIndex::release; }

  /// @returns true if in the delayed stage
  inline bool isDelayed() const noexcept { return stageIndex_ == StageIndex::delay; }

  /// @returns true if in the attack stage
  inline bool isAttack() const noexcept { return stageIndex_ == StageIndex::attack; }

  /// @returns true if in the release stage
  inline bool isRelease() const noexcept { return stageIndex_ == StageIndex::release; }

  /// @returns number of samples remaining in the current state
  inline int counter() const noexcept { return counter_; }

  /// @returns stage at given index
  inline const Stage& stage(StageIndex index) const noexcept { return stages_[index]; }

protected:

  /**
   Construct a NULL generator, one that will never emit any non-zero values. To be useful, a generator must be
   configured with a State that holds the stage definitions to use.

   @param voiceIndex the voice index this belongs to
   */
  Generator(size_t voiceIndex, const char* logTag) noexcept;

  /// NOTE: only used for testing via EnvelopeTestInjector
  Generator(Float sampleRate, const char* logTag, size_t voiceIndex, Float delay, Float attack, Float hold, Float decay,
            int sustain, Float release) noexcept;

  /// @returns configured sustain level. NOTE: only used for testing
  Float sustainLevel() const noexcept { return sustainLevel_; }

  /// @returns the current envelope value.
  inline Float value() const noexcept { return value_; }

  /**
   Calculate the next envelope value. This must be called on every sample for proper timing of the stages.
   NOTE: part of render processing chain

   @returns the new envelope value.
   */
  inline Float getNextValue() noexcept {
    if (!checkForNextStage()) return 0_F;
    value_ = stages_[stageIndex_].next(value_);
    if (value_ < 0_F) { // Do not check for 0.0 since that is a valid starting state.
      stop();
    } else {
      if (value_ > 1_F) {
        value_ = 1_F;
      }
      --counter_;
      checkForNextStage();
    }
    return value_;
  }

  void configureVolumeEnvelope(const State& state) noexcept;

  void configureModulationEnvelope(const State& state) noexcept;

private:

  static const char* stageName(StageIndex index) noexcept {
    switch (index) {
      case StageIndex::delay:   return "DELAY";
      case StageIndex::attack:  return "ATTACK";
      case StageIndex::hold:    return "HOLD";
      case StageIndex::decay:   return "DECAY";
      case StageIndex::sustain: return "SUSTAIN";
      case StageIndex::release: return "RELEASE";
      case StageIndex::idle:    return "IDLE";
    }
  }

  /**
   Enter a new stage.

   @param next the stage to enter
   */
  inline void enterStage(StageIndex next) noexcept {
    os_log_info(log_, "enterStage %zu - old: %s new: %s value: %f", voiceIndex_, stageName(stageIndex_),
                stageName(next), value_);
    stageIndex_ = next;
    if (next != StageIndex::idle) {
      counter_ = stages_[stageIndex_].durationInSamples();
    }
  }

  /**
   Check if transition to the next stage is warranted.

   @returns true if the envelope is still active
   */
  inline bool checkForNextStage() noexcept {
    while (counter_ == 0) {
      switch (stageIndex_) {
        case StageIndex::delay:   enterStage(StageIndex::attack); continue;
        case StageIndex::attack:  enterStage(StageIndex::hold); continue;
        case StageIndex::hold:    enterStage(StageIndex::decay); continue;
        case StageIndex::decay:   enterStage(StageIndex::sustain); continue;
        case StageIndex::sustain: enterStage(StageIndex::release); continue; // this will actually never happen
        case StageIndex::release: stop(); return false;
        case StageIndex::idle:    return false;
      }
    }
    return true;
  }

  Stages stages_{};
  StageIndex stageIndex_{StageIndex::idle};
  int counter_{0};
  Float value_{0_F};
  Float sustainLevel_{0_F};
  const char* logTag_;
  const size_t voiceIndex_;
  const os_log_t log_;
};

} // namespace SF2::Render::Envelope
