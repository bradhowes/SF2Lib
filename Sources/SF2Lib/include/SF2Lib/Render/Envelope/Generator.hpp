// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

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

/**
 Generator of values for the SF2 volume/filter envelopes. An SF2 envelope contains 6 stages:

 - Delay -- number of samples to delay the beginning of the attack stage
 - Attack -- number of samples to ramp up from 0.0 to 1.0 in a exponential way
 - Hold -- number of samples to hold the envelope at 1.0 before entering the decay stage.
 - Decay -- number of samples to lower the envelope from 1.0 to the sustain level in a linear descent
 - Sustain -- a stage that lasts as long as a note is held down
 - Release -- number of samples to go from sustain level to ~0 in a linear descent

 The envelope will remain in the idle state until `gate(true)` is invoked. It will remain in the sustain stage until
 `gate(false)` is invoked at which point it will enter the `release` stage. Although the stages above are listed in the
 order in which they are performed, any stage will transition to the `release` stage upon a `gate(false)`
 call.

 The more traditional ADSR (attack, decay, sustain, release) envelope can be achieved by setting the delay and hold
 durations to zero.
 */
class Generator {
public:
  using Index = Entity::Generator::Index;
  using State = Render::Voice::State::State;

  /**
   Collection of states for all of the stages in an SF2 envelope.
   */
  struct Stages : public std::array<Stage, static_cast<size_t>(StageIndex::release) + 1> {
    using super = std::array<Stage, static_cast<size_t>(StageIndex::release) + 1>;

    Stage& operator[](const StageIndex& index) {
      return super::operator[](static_cast<super::size_type>(index));
    }

    const Stage& operator[](const StageIndex& index) const {
      return super::operator[](static_cast<super::size_type>(index));
    }
  };

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
  bool isActive() const noexcept { return stageIndex_ != StageIndex::idle; }

  /// @returns true if the generator is active and has not yet reached the release state
  bool isGated() const noexcept { return isActive() && stageIndex_ != StageIndex::release; }

  /// @returns true if in the delayed stage
  bool isDelayed() const noexcept { return stageIndex_ == StageIndex::delay; }

  /// @returns true if in the attack stage
  bool isAttack() const noexcept { return stageIndex_ == StageIndex::attack; }

  /// @returns true if in the release stage
  bool isRelease() const noexcept { return stageIndex_ == StageIndex::release; }

  int counter() const noexcept { return counter_; }

  /// @returns stage at given index
  const Stage& stage(StageIndex index) const noexcept { return stages_[index]; }

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

  /// @returns the current envelope value.
  Float value() const noexcept { return value_; }

  /**
   Calculate the next envelope value. This must be called on every sample for proper timing of the stages.
   NOTE: part of render processing chain

   @returns the new envelope value.
   */
  Float getNextValue() noexcept {
    if (!checkForNextStage()) {
      value_ = 0.0_F;
    } else {
      value_ = stages_[stageIndex_].next(value_);
      if (value_ < 0.0_F) {
        stop();
      } else {
        --counter_;
        checkForNextStage();
      }
    }
    return value_;
  }

  /// @returns configured sustain level
  Float sustainLevel() const noexcept { return sustainLevel_; }

  void configureVolumeEnvelope(const State& state) noexcept;

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
        case StageIndex::delay: enterStage(StageIndex::attack); break;
        case StageIndex::attack: enterStage(StageIndex::hold); break;
        case StageIndex::hold: enterStage(StageIndex::decay); break;
        case StageIndex::decay: enterStage(StageIndex::sustain); break;
        case StageIndex::sustain: enterStage(StageIndex::release); break;
        case StageIndex::release: enterStage(StageIndex::idle); return false;
        case StageIndex::idle: return false;
      }
    }
    return true;
  }

  /**
   Obtain the number of samples for a given sample rate and duration.

   @param seconds the amount of time to use in the calculation represented in timecents
   @returns the number of samples
   */
  static constexpr int sampleCountFor(Float sampleRate, Float seconds) noexcept {
    return int(round(sampleRate * seconds));
  }

  Stages stages_{};
  StageIndex stageIndex_{StageIndex::idle};
  int counter_{0};
  Float value_{0.0};
  Float sustainLevel_{0.0};
  const size_t voiceIndex_;
  const os_log_t log_;
};

} // namespace SF2::Render::Envelope
