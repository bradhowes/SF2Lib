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
struct Stages : public std::array<Stage, static_cast<size_t>(StageIndex::release) + 1> {
  using super = std::array<Stage, static_cast<size_t>(StageIndex::release) + 1>;

  Stage& operator[](const StageIndex& index) { return super::operator[](static_cast<super::size_type>(index)); }
  const Stage& operator[](const StageIndex& index) const { return super::operator[](static_cast<super::size_type>(index)); }
};

/**
 Generator of values for the SF2 volume/filter envelopes. An envelope contains 6 stages:

 - Delay -- number of samples to delay the beginning of the attack stage
 - Attack -- number of samples to ramp up from 0.0 to 1.0. Also supports non-linear curvature.
 - Hold -- number of samples to hold the envelope at 1.0 before entering the decay stage.
 - Decay -- number of samples to lower the envelope from 1.0 to the sustain level
 - Sustain -- a stage that lasts as long as a note is held down
 - Release -- number of samples to go from sustain level to 0.0

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

  inline static constexpr Float defaultCurvature = 0.01;

  Generator(Float sampleRate) : sampleRate_{sampleRate} {}

  /**
   Create new envelope for volume changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  void configureVolumeEnvelope(const State& state) noexcept {
    Float sustainLevel = volEnvSustain(state);
    stages_[StageIndex::delay].setDelay(samplesFor(state.modulated(Index::delayVolumeEnvelope)));
    stages_[StageIndex::attack].setAttack(samplesFor(state.modulated(Index::attackVolumeEnvelope)), defaultCurvature);
    stages_[StageIndex::hold].setHold(samplesFor(state.modulated(Index::holdVolumeEnvelope) + keyToVolEnvHold(state)));
    stages_[StageIndex::decay].setDecay(samplesFor(state.modulated(Index::decayVolumeEnvelope) +
                                                   keyToVolEnvDecay(state)), defaultCurvature, sustainLevel);
    stages_[StageIndex::sustain].setSustain(sustainLevel);
    stages_[StageIndex::release].setRelease(samplesFor(state.modulated(Index::releaseVolumeEnvelope)), defaultCurvature,
                                            sustainLevel);
    gate(true);
  }

  /**
   Create new envelope for modulation changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  void configureModulationEnvelope(const State& state) noexcept {
    Float sustainLevel = modEnvSustain(state);
    stages_[StageIndex::delay].setDelay(samplesFor(state.modulated(Index::delayModulatorEnvelope)));
    stages_[StageIndex::attack].setAttack(samplesFor(state.modulated(Index::attackModulatorEnvelope)),
                                          defaultCurvature);
    stages_[StageIndex::hold].setHold(samplesFor(state.modulated(Index::holdModulatorEnvelope) +
                                                 keyToModEnvHold(state)));
    stages_[StageIndex::decay].setDecay(samplesFor(state.modulated(Index::decayModulatorEnvelope) +
                                                   keyToModEnvDecay(state)), defaultCurvature,
                                        sustainLevel);
    stages_[StageIndex::sustain].setSustain(sustainLevel);
    stages_[StageIndex::release].setRelease(samplesFor(state.modulated(Index::releaseModulatorEnvelope)),
                                            defaultCurvature, sustainLevel);
    gate(true);
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

  const Stage& stage(StageIndex index) const noexcept { return stages_[index]; }

  StageIndex activeIndex() const { return stageIndex_; }

  // const Stage& stage(StageIndex index) const { return stages_[index]; }
  
  /// @returns true if the generator still has values to emit
  bool isActive() const noexcept { return stageIndex_ != StageIndex::idle; }

  /// @returns true if the generator is active and has not yet reached the release state
  bool isGated() const noexcept { return isActive() && stageIndex_ != StageIndex::release; }

  bool isDelayed() const noexcept { return stageIndex_ == StageIndex::delay; }

  /// @returns the current envelope value.
  Float value() const noexcept { return value_; }

  Float sustain() const noexcept { return stages_[StageIndex::sustain].initial(); }

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

private:

  const Stage& activeStage() const noexcept { return stages_[stageIndex_]; }

  /// NOTE: only used for testing via EnvelopeTestInjector
  Generator(Float sampleRate, Float delay, Float attack, Float hold, Float decay, Float sustain, Float release)
  : sampleRate_{sampleRate}
  {
    stages_[StageIndex::delay].setDelay(int(round(sampleRate_ * delay)));
    stages_[StageIndex::attack].setAttack(int(round(sampleRate_ * attack)), defaultCurvature);
    stages_[StageIndex::hold].setHold(int(round(sampleRate_ * hold)));
    stages_[StageIndex::decay].setDecay(int(round(sampleRate_ * decay)), defaultCurvature, sustain);
    stages_[StageIndex::sustain].setSustain(sustain);
    stages_[StageIndex::release].setRelease(int(round(sampleRate_ * release)), defaultCurvature, sustain);
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

  /// @returns the sustain level for the modulator envelope (gain)
  static Float envSustain(const State& state, Index gen) noexcept {
    assert(gen == Index::sustainVolumeEnvelope || gen == Index::sustainModulatorEnvelope);
    return 1.0 - state.modulated(gen) / 1000.0;
  }

  /// @returns the sustain level for the volume envelope (gain)
  static Float volEnvSustain(const State& state) noexcept {
    return envSustain(state, Index::sustainVolumeEnvelope);
  }

  /// @returns the sustain level for the modulator envelope
  static Float modEnvSustain(const State& state) noexcept {
    return envSustain(state, Index::sustainModulatorEnvelope);
  }

  /**
   Obtain the number of samples for a given sample rate and duration.

   @param cents the amount of time to use in the calculation represented in timecents
   @returns the number of samples
   */
  int samplesFor(Float cents) noexcept {
    auto seconds = DSP::centsToSeconds(cents);
    auto samples = int(round(sampleRate_ * seconds));
    os_log_debug(log_, "samplesFor: %g -> %g -> %d", cents, seconds, samples);
    return samples;
  }

  /**
   Update the envelope value and see if it is lower than the given floor. If so, transition to the next stage.
   Otherwise, check to see if the stage duration is complete.
   */
  void updateAndCompare(Float floor, StageIndex next) noexcept {
    updateValue();
    unlikely(value_ < floor) ? enterStage(next) : checkIfEndStage(next);
  }

  Float sustainLevel() const noexcept { return stages_[StageIndex::sustain].initial(); }

  void updateValue() noexcept { value_ = activeStage().next(value_); }

  void checkIfEndStage(StageIndex next) noexcept { if (unlikely(--counter_ <= 0)) enterStage(next); }

  int activeDurationInSamples() const noexcept { return activeStage().durationInSamples(); }

  void enterStage(StageIndex next) noexcept {
    stageIndex_ = next;

    // NOTE: if a stage has no duration then we move to the next one by falling thru some of the cases.
    switch (next) {
      case StageIndex::delay:
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::attack;

      case StageIndex::attack:
        value_ = activeStage().initial();
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::hold;

      case StageIndex::hold:
        value_ = activeStage().initial();
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::decay;

      case StageIndex::decay:
        value_ = activeStage().initial();
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::sustain;

      case StageIndex::sustain:
        value_ = activeStage().initial();
        break;

      case StageIndex::release:
        if (activeDurationInSamples()) break;
        stageIndex_ = StageIndex::idle;

      case StageIndex::idle:
        value_ = 0.0;
        return;
    }

    counter_ = activeDurationInSamples();
  }

  Stages stages_{};
  StageIndex stageIndex_{StageIndex::idle};
  int counter_{0};
  Float value_{0.0};
  Float sampleRate_;
  os_log_t log_{os_log_create("SF2Lib", "Envelope")};
  friend class EnvelopeTestInjector;
};

} // namespace SF2::Render::Envelope
