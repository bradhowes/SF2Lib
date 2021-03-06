// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <cmath>
#include <limits>
#include <utility>

#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Envelope/Stage.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

/**
 Representation of an envelope with various stages that have their own timing characteristics and levels.
 */
namespace SF2::Render::Envelope {

/**
 Collection of states for all of the stages in an SF2 envelope.
 */
using Stages = std::array<Stage, static_cast<size_t>(StageIndex::release) + 1>;

/**
 Generator of values for the SF2 volume/filter envelopes. An envelope contains 6 stages:

 - Delay -- number of seconds to delay the beginning of the attack stage
 - Attack -- number of seconds to ramp up from 0.0 to 1.0. Also supports non-linear curvature.
 - Hold -- number of seconds to hold the envelope at 1.0 before entering the decay stage.
 - Decay -- number of seconds to lower the envelope from 1.0 to the sustain level
 - Sustain -- a stage that lasts as long as a note is held down
 - Release -- number of seconds to go from sustain level to 0.0

 The envelope will remain in the idle state until `gate(true)` is invoked. It will remain in the sustain stage until
 `gate(false)` is invoked at which point it will enter the `release` stage. Although the stages above are listed in the
 order in which they are performed, any stage will transition to the `release` stage upon a `gate(false)`
 call.

 The more traditional ADSR (attack, decay, sustain, release) envelope can be achieved by setting the delay and hold
 durations to zero (0.0).
 */
class Generator {
public:
  using Index = Entity::Generator::Index;
  using State = Render::Voice::State::State;

  inline static constexpr Float defaultCurvature = 0.01f;

  Generator() = default;

  Generator(Generator&& rhs) noexcept
  : stages_{std::move(rhs.stages_)}, stageIndex_{rhs.stageIndex_}, counter_{rhs.counter_}, value_{rhs.value_}
  {}

  Generator& operator=(Generator&& rhs) noexcept {
    stages_ = std::move(rhs.stages_);
    stageIndex_ = rhs.stageIndex_;
    counter_ = rhs.counter_;
    value_ = rhs.value_;
    return *this;
  }

  /**
   Create new envelope for volume changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  static Generator forVol(const State& state) noexcept {
    return Generator(state.sampleRate(),
                     DSP::centsToSeconds(state.modulated(Index::delayVolumeEnvelope)),
                     DSP::centsToSeconds(state.modulated(Index::attackVolumeEnvelope)),
                     DSP::centsToSeconds(state.modulated(Index::holdVolumeEnvelope) + keyToVolEnvHold(state)),
                     DSP::centsToSeconds(state.modulated(Index::decayVolumeEnvelope) + keyToVolEnvDecay(state)),
                     volEnvSustain(state),
                     DSP::centsToSeconds(state.modulated(Index::releaseVolumeEnvelope)),
                     true);
  }

  /**
   Create new envelope for modulation changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  static Generator forMod(const State& state) noexcept {
    return Generator(state.sampleRate(),
                     DSP::centsToSeconds(state.modulated(Index::delayModulatorEnvelope)),
                     DSP::centsToSeconds(state.modulated(Index::attackModulatorEnvelope)),
                     DSP::centsToSeconds(state.modulated(Index::holdModulatorEnvelope) + keyToModEnvHold(state)),
                     DSP::centsToSeconds(state.modulated(Index::decayModulatorEnvelope) + keyToModEnvDecay(state)),
                     modEnvSustain(state),
                     DSP::centsToSeconds(state.modulated(Index::releaseModulatorEnvelope)),
                     true);
  }

  /**
   Set the status of a note playing. When true, the envelope begins proper. When set to false, the envelope will
   jump to the release stage.
   */
  void gate(bool noteOn) noexcept {
    if (noteOn) {
      value_ = 0.0;
      enterStage(StageIndex::delay);
    }
    else if (stageIndex_ != StageIndex::idle) {
      enterStage(StageIndex::release);
    }
  }

  /// @returns the currently active stage.
  StageIndex stage() const noexcept { return stageIndex_; }

  /// @returns true if the generator still has values to emit
  bool isActive() const noexcept { return stageIndex_ != StageIndex::idle; }

  /// @returns true if the generator is active and has not yet reached the release state
  bool isGated() const noexcept { return isActive() && stageIndex_ != StageIndex::release; }

  bool isDelayed() const noexcept { return stageIndex_ == StageIndex::delay; }

  /// @returns the current envelope value.
  Float value() const noexcept { return value_; }

  /**
   Calculate the next envelope value. This must be called on every sample for proper timing of the stages.

   @returns the new envelope value.
   */
  Float getNextValue() noexcept {
    switch (stageIndex_) {
      case StageIndex::delay: checkIfEndStage(StageIndex::attack); break;
      case StageIndex::attack: updateValue(); checkIfEndStage(StageIndex::hold); break;
      case StageIndex::hold: checkIfEndStage(StageIndex::decay); break;
      case StageIndex::decay: updateAndCompare(sustainLevel(), StageIndex::sustain); break;
      case StageIndex::release: updateAndCompare(DSP::NoiseFloor, StageIndex::idle); break;
      default: break;
    }

    return value_;
  }

  const Stage& operator[](StageIndex stageIndex) const noexcept { return stages_[static_cast<size_t>(stageIndex)]; }

private:

  Generator(Float sampleRate, Float delay, Float attack, Float hold, Float decay, Float sustain, Float release,
            bool noteOn = false) noexcept : stages_{
    Stage::Delay(samplesFor(sampleRate, delay)),
    Stage::Attack(samplesFor(sampleRate, attack), defaultCurvature),
    Stage::Hold(samplesFor(sampleRate, hold)),
    Stage::Decay(samplesFor(sampleRate, decay), defaultCurvature, sustain),
    Stage::Sustain(sustain),
    Stage::Release(samplesFor(sampleRate, release), defaultCurvature, sustain)
  }
  {
    if (noteOn) gate(true);
  }

  /**
   Obtain a generator value that is scaled by the MIDI key value. Per the spec, key 60 is unchanged. Keys higher will
   scale positively, and keys lower than 60 will scale negatively.

   @param gen the generator holding the timecents/semitone scaling factor
   @returns result of generator value x (60 - key)
   */
  static Float keyModEnv(const State& state, Index gen) noexcept {
    assert(gen == Index::midiKeyToVolumeEnvelopeHold ||
           gen == Index::midiKeyToVolumeEnvelopeDecay ||
           gen == Index::midiKeyToModulatorEnvelopeHold ||
           gen == Index::midiKeyToModulatorEnvelopeDecay);
    return state.modulated(gen) * (60 - state.key());
  }

  /// @returns the adjustment to the volume envelope's hold stage timing based on the MIDI key event
  static Float keyToVolEnvHold(const State& state) noexcept {
    return keyModEnv(state, Index::midiKeyToVolumeEnvelopeHold);
  }

  /// @returns the adjustment to the volume envelope's decay stage timing based on the MIDI key event
  static Float keyToVolEnvDecay(const State& state) noexcept {
    return keyModEnv(state, Index::midiKeyToVolumeEnvelopeDecay);
  }

  /// @returns the adjustment to the modulator envelope's hold stage timing based on the MIDI key event
  static Float keyToModEnvHold(const State& state) noexcept {
    return keyModEnv(state, Index::midiKeyToModulatorEnvelopeHold);
  }

  /// @returns the adjustment to the modulator envelope's decay stage timing based on the MIDI key event
  static Float keyToModEnvDecay(const State& state) noexcept {
    return keyModEnv(state, Index::midiKeyToModulatorEnvelopeDecay);
  }

  static Float envSustain(const State& state, Index gen) noexcept {
    assert(gen == Index::sustainVolumeEnvelope || gen == Index::sustainModulatorEnvelope);
    return 1.0f - state.modulated(gen) / 1000.0f;
  }

  /// @returns the sustain level for the volume envelope (gain)
  static Float volEnvSustain(const State& state) noexcept {
    return envSustain(state, Index::sustainVolumeEnvelope);
  }

  /// @returns the sustain level for the modulator envelope
  static Float modEnvSustain(const State& state) noexcept {
    return envSustain(state, Index::sustainModulatorEnvelope);
  }

  static int samplesFor(Float sampleRate, Float duration) noexcept { return int(round(sampleRate * duration)); }

  void updateAndCompare(Float floor, StageIndex next) noexcept {
    updateValue();
    unlikely(value_ < floor) ? enterStage(next) : checkIfEndStage(next);
  }

  const Stage& active() const noexcept { return stage(stageIndex_); }

  const Stage& stage(StageIndex stageIndex) const noexcept { return stages_[static_cast<size_t>(stageIndex)]; }

  Float sustainLevel() const noexcept { return stage(StageIndex::sustain).initial_; }

  void updateValue() noexcept { value_ = active().next(value_); }

  void checkIfEndStage(StageIndex next) noexcept {
    if (unlikely(--counter_ == 0)) {
      enterStage(next);
    }
  }

  int activeDurationInSamples() const noexcept { return active().durationInSamples_; }

  void enterStage(StageIndex next) noexcept {
    stageIndex_ = next;
    switch (stageIndex_) {
      case StageIndex::delay:
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::attack;

      case StageIndex::attack:
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::hold;

      case StageIndex::hold:
        value_ = 1.0;
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::decay;

      case StageIndex::decay:
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::sustain;

      case StageIndex::sustain:
        value_ = active().initial_;
        break;

      case StageIndex::release:
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::idle;
        value_ = 0.0;

      case StageIndex::idle: return;
    }

    counter_ = activeDurationInSamples();
  }

  Stages stages_{};
  StageIndex stageIndex_{StageIndex::idle};
  int counter_{0};
  Float value_{0.0};

  friend class EnvelopeTestInjector;
};

} // namespace SF2::Render::Envelope
