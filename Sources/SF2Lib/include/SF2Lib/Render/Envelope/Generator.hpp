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

enum struct Kind {
  volume = 1,
  modulation = 2
};

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
template <enum struct Kind Kind>
class Generator {
public:
  using Index = Entity::Generator::Index;
  using State = Render::Voice::State::State;

  /**
   Custom type for values from this LFO. Each LFO "kind" has its own value type in order to catch mistakes wiring with
   the wrong one.
   */
  struct Value {
    Float val;
    explicit Value(Float v) noexcept : val{v} {}
  };

  /// Obtain a log tag to use based on the EnvelopeKind enum value.
  static constexpr const char* logTag() {
    switch (Kind) {
      case Kind::volume: return "Generator<Volume>";
      case Kind::modulation: return "Generator<Modulation>";
      default: throw "invalid Kind";
    }
  }

  /**
   Construct a NULL generator, one that will never emit any non-zero values. To be useful, a generator must be
   configured with a State that holds the stage definitions to use.

   @param voiceIndex the voice index this belongs to
   */
  Generator(size_t voiceIndex)
  : voiceIndex_{voiceIndex}, log_{os_log_create("SF2Lib", logTag())}
  {}

  /**
   Create new envelope for volume changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  void configure(const State& state) noexcept {
    if (Kind == Kind::volume) {
      configureVolumeEnvelope(state);
    } else {
      configureModulationEnvelope(state);
    }
  }

  /**
   Set the status of a note playing. When true, the envelope begins proper. When set to false, the envelope will
   jump to the release stage.
   */
  void gate(bool noteOn) noexcept {
    if (noteOn) {
      counter_ = 0;
      value_ = 0.0;
      enterStage(StageIndex::delay);
    } else if (stageIndex_ != StageIndex::idle) {
      // NOTE: we need to recalculate the duration of the release stage if the value is lower than the sustain level
      enterStage(StageIndex::release);
    }
  }

  void stop() noexcept {
    stageIndex_ = StageIndex::idle;
    value_ = 0.0;
  }

  const Stage& stage(StageIndex index) const noexcept { return stages_[index]; }

  StageIndex activeIndex() const { return stageIndex_; }

  // const Stage& stage(StageIndex index) const { return stages_[index]; }
  
  /// @returns true if the generator still has values to emit
  bool isActive() const noexcept { return stageIndex_ != StageIndex::idle; }

  /// @returns true if the generator is active and has not yet reached the release state
  bool isGated() const noexcept { return isActive() && stageIndex_ != StageIndex::release; }

  /// @returns true if the generate is in the delayed state
  bool isDelayed() const noexcept { return stageIndex_ == StageIndex::delay; }

  bool isAttack() const noexcept { return stageIndex_ == StageIndex::attack; }

  /// @returns the current envelope value.
  Value value() const noexcept { return Value(value_); }

  /**
   Calculate the next envelope value. This must be called on every sample for proper timing of the stages.

   @returns the new envelope value.
   */
  Value getNextValue() noexcept {
    switch (stageIndex_) {
      case StageIndex::delay: checkIfEndStage(StageIndex::attack); break;
      case StageIndex::attack: updateValue(); checkIfEndStage(StageIndex::hold); break;
      case StageIndex::hold: checkIfEndStage(StageIndex::decay); break;
      case StageIndex::decay: updateValue(); checkIfEndStage(StageIndex::sustain); break;
      case StageIndex::release: updateValue(); checkIfEndStage(StageIndex::idle); break;
      default: break;
    }
    return value();
  }

private:

  /**
   Create new envelope for volume changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  void configureVolumeEnvelope(const State& state) noexcept {
    Float sustainLevel = volEnvSustain(state);

    auto delayTimecents = state.modulated(Index::delayVolumeEnvelope);
    stages_[StageIndex::delay].setDelay(samplesFor(state.sampleRate(),
                                                   delayTimecentsToSeconds(delayTimecents)));

    auto attackTimecents = state.modulated(Index::attackVolumeEnvelope);
    stages_[StageIndex::attack].setAttack(samplesFor(state.sampleRate(),
                                                     attackTimecentsToSeconds(attackTimecents)));

    auto holdTimecents = state.modulated(Index::holdVolumeEnvelope) + midiKeyVolumeEnvelopeHoldAdjustment(state);
    stages_[StageIndex::hold].setHold(samplesFor(state.sampleRate(),
                                                 holdTimecentsToSeconds(holdTimecents)));

    auto decayTimecents = state.modulated(Index::decayVolumeEnvelope) + midiKeyVolumeEnvelopeDecayAdjustment(state);
    stages_[StageIndex::decay].setDecay(samplesFor(state.sampleRate(),
                                                   decayTimecentsToSeconds(decayTimecents)), sustainLevel);

    stages_[StageIndex::sustain].setSustain(sustainLevel);

    auto releaseTimecents = state.modulated(Index::releaseVolumeEnvelope);
    stages_[StageIndex::release].setRelease(samplesFor(state.sampleRate(),
                                                       releaseTimecentsToSeconds(releaseTimecents)), sustainLevel);

    gate(true);
  }

  /**
   Create new envelope for modulation changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  void configureModulationEnvelope(const State& state) noexcept {
    Float sustainLevel = modEnvSustain(state);

    auto delayTimecents = state.modulated(Index::delayModulatorEnvelope);
    stages_[StageIndex::delay].setDelay(samplesFor(state.sampleRate(),
                                                   delayTimecentsToSeconds(delayTimecents)));

    auto attackTimecents = state.modulated(Index::attackModulatorEnvelope);
    stages_[StageIndex::attack].setAttack(samplesFor(state.sampleRate(),
                                                     attackTimecentsToSeconds(attackTimecents)));

    auto holdTimecents = state.modulated(Index::holdModulatorEnvelope) + midiKeyModulatorEnvelopeHoldAdjustment(state);
    stages_[StageIndex::hold].setHold(samplesFor(state.sampleRate(),
                                                 holdTimecentsToSeconds(holdTimecents)));

    auto decayTimecents = state.modulated(Index::decayModulatorEnvelope) + midiKeyModulatorEnvelopeDecayAdjustment(state);
    stages_[StageIndex::decay].setDecay(samplesFor(state.sampleRate(),
                                                   decayTimecentsToSeconds(decayTimecents)), sustainLevel);

    stages_[StageIndex::sustain].setSustain(sustainLevel);

    auto releaseTimecents = state.modulated(Index::releaseModulatorEnvelope);
    stages_[StageIndex::release].setRelease(samplesFor(state.sampleRate(),
                                                       releaseTimecentsToSeconds(releaseTimecents)), sustainLevel);

    gate(true);
  }

  inline static constexpr Float lowerBoundTimecents = -12'000.0;

  static inline Float delayTimecentsToSeconds(Float value) noexcept {
    return (value <= -32768.0) ? 0.0 : DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 5000.0));
  }

  inline Float attackTimecentsToSeconds(Float value) noexcept {
    return (value <= -32768.0) ? 0.0 : DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 8000.0));
  }

  inline Float holdTimecentsToSeconds(Float value) noexcept {
    return DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 5000.0));
  }

  inline Float decayTimecentsToSeconds(Float value) noexcept {
    return DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 8000.0));
  }

  inline Float releaseTimecentsToSeconds(Float value) noexcept {
    return DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 5000.0));
  }

  Float sustain() const noexcept { return stages_[StageIndex::sustain].initial(); }

  const Stage& activeStage() const noexcept { return stages_[stageIndex_]; }

  /// NOTE: only used for testing via EnvelopeTestInjector
  Generator(Float sampleRate, size_t voiceIndex, Float delay, Float attack, Float hold, Float decay,
            int sustain, Float release)
  : voiceIndex_{voiceIndex}, log_{os_log_create("SF2Lib", logTag())}
  {
    Float normSustain = 1.0f - sustain / Float(1000.0);
    stages_[StageIndex::delay].setDelay(int(round(sampleRate * delay)));
    stages_[StageIndex::attack].setAttack(int(round(sampleRate * attack)));
    stages_[StageIndex::hold].setHold(int(round(sampleRate * hold)));
    stages_[StageIndex::decay].setDecay(int(round(sampleRate * decay)), normSustain);
    stages_[StageIndex::sustain].setSustain(normSustain);
    stages_[StageIndex::release].setRelease(int(round(sampleRate * release)), normSustain);
  }

  /// @returns the adjustment to the volume envelope's hold stage timing based on the MIDI key event
  static Float midiKeyVolumeEnvelopeHoldAdjustment(const State& state) noexcept {
    return midiKeyEnvelopeScaling(state, Index::midiKeyToVolumeEnvelopeHold);
  }

  /// @returns the adjustment to the volume envelope's decay stage timing based on the MIDI key event
  static Float midiKeyVolumeEnvelopeDecayAdjustment(const State& state) noexcept {
    return midiKeyEnvelopeScaling(state, Index::midiKeyToVolumeEnvelopeDecay);
  }

  /// @returns the adjustment to the modulator envelope's hold stage timing based on the MIDI key event
  static Float midiKeyModulatorEnvelopeHoldAdjustment(const State& state) noexcept {
    return midiKeyEnvelopeScaling(state, Index::midiKeyToModulatorEnvelopeHold);
  }

  /// @returns the adjustment to the modulator envelope's decay stage timing based on the MIDI key event
  static Float midiKeyModulatorEnvelopeDecayAdjustment(const State& state) noexcept {
    return midiKeyEnvelopeScaling(state, Index::midiKeyToModulatorEnvelopeDecay);
  }

  /**
   Obtain a generator value that is scaled by the MIDI key value. Per the spec, key 60 is unchanged. Keys higher will
   scale positively, and keys lower than 60 will scale negatively.

   @param gen the generator holding the timecents/semitone scaling factor
   @returns result of generator value x (60 - key)
   */
  static Float midiKeyEnvelopeScaling(const State& state, Index gen) noexcept {
    assert(gen == Index::midiKeyToVolumeEnvelopeHold ||
           gen == Index::midiKeyToVolumeEnvelopeDecay ||
           gen == Index::midiKeyToModulatorEnvelopeHold ||
           gen == Index::midiKeyToModulatorEnvelopeDecay);
    auto value = state.modulated(gen);
    auto scaling = 60 - state.key();
    return value * scaling;
  }

  /// @returns the sustain level for the modulator envelope
  static Float modEnvSustain(const State& state) noexcept {
    /**
     Spec 8.1.2 sustainModEnv

     This is the decrease in level, expressed in 0.1% units, to which the Modulation Envelope value ramps during the
     decay phase. For the Modulation Envelope, the sustain level is properly expressed in percent of full scale.
     Because the volume envelope sustain level is expressed as an attenuation from full scale, the sustain level is
     analogously expressed as a decrease from full scale. A value of 0 indicates the sustain level is full level; this
     implies a zero duration of decay phase regardless of decay time. A positive value indicates a decay to the
     corresponding level. Values less than zero are to be interpreted as zero; values above 1000 are to be interpreted
     as 1000. For example, a sustain level which corresponds to an absolute value 40% of peak would be 600.

     Our stages always work in normalized values, so convert percentage to a sustain level.
     */
    return 1.0f - DSP::tenthPercentageToNormalized(state.modulated(Index::sustainModulatorEnvelope));
  }

  /// @returns the sustain level for the volume envelope (gain)
  static Float volEnvSustain(const State& state) noexcept {
    /**
     Spec 8.1.2 sustainVolEnv

     This is the decrease in level, expressed in centibels, to which the Volume Envelope value ramps during the decay
     phase. For the Volume Envelope, the sustain level is best expressed in centibels of attenuation from full scale.
     A value of 0 indicates the sustain level is full level; this implies a zero duration of decay phase regardless of
     decay time. A positive value indicates a decay to the corresponding level. Values less than zero are to be
     interpreted as zero; conventionally 1000 indicates full attenuation. For example, a sustain level which
     corresponds to an absolute value 12dB below of peak would be 120.

     Our stages always work in normalized values, so convert centibels to an attenuation value.
     */
    return DSP::centibelsToAttenuation(state.modulated(Index::sustainVolumeEnvelope));
  }

  /**
   Obtain the number of samples for a given sample rate and duration.

   @param seconds the amount of time to use in the calculation represented in timecents
   @returns the number of samples
   */
  int samplesFor(Float sampleRate, Float seconds) noexcept {
    auto samples = int(round(sampleRate * seconds));
    return samples;
  }

  Float sustainLevel() const noexcept { return stages_[StageIndex::sustain].initial(); }

  void updateValue() noexcept { value_ = activeStage().next(value_); }

  void checkIfEndStage(StageIndex next) noexcept { if (--counter_ <= 0) enterStage(next); }

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
  const size_t voiceIndex_;
  const os_log_t log_;
  friend class EnvelopeTestInjector;
};

using Volume = Generator<Kind::volume>;
using Modulation = Generator<Kind::modulation>;

} // namespace SF2::Render::Envelope
