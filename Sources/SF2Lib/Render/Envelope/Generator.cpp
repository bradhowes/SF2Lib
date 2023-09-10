// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Envelope/Generator.hpp"

using namespace SF2;
using namespace SF2::Render::Envelope;

static constexpr Float lowerBoundTimecents = -12'000.0;

/**
 Obtain a generator value that is scaled by the MIDI key value. Per the spec, key 60 is unchanged. Keys higher will
 scale positively, and keys lower than 60 will scale negatively.

 @param gen the generator holding the timecents/semitone scaling factor
 @returns result of generator value x (60 - key)
 */
constexpr Float midiKeyEnvelopeScaling(const Generator::State& state, Generator::Index gen) noexcept {
  auto value = state.modulated(gen);
  auto scaling = 60 - state.key();
  return value * scaling;
}

constexpr Float delayTimecentsToSeconds(Float value) noexcept {
  return (value <= -32'768.0) ? 0.0 : DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 5'000.0));
}

constexpr Float attackTimecentsToSeconds(Float value) noexcept {
  return (value <= -32'768.0) ? 0.0 : DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 8'000.0));
}

constexpr Float holdTimecentsToSeconds(Float value) noexcept {
  return DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 5'000.0));
}

constexpr Float decayTimecentsToSeconds(Float value) noexcept {
  return DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 8'000.0));
}

constexpr Float releaseTimecentsToSeconds(Float value) noexcept {
  return DSP::centsToSeconds(DSP::clamp(value, lowerBoundTimecents, 5'000.0));
}

constexpr Float midiKeyVolumeEnvelopeHoldAdjustment(const Generator::State& state) noexcept {
  return midiKeyEnvelopeScaling(state, Generator::Index::midiKeyToVolumeEnvelopeHold);
}

constexpr Float midiKeyVolumeEnvelopeDecayAdjustment(const Generator::State& state) noexcept {
  return midiKeyEnvelopeScaling(state, Generator::Index::midiKeyToVolumeEnvelopeDecay);
}

constexpr Float midiKeyModulatorEnvelopeHoldAdjustment(const Generator::State& state) noexcept {
  return midiKeyEnvelopeScaling(state, Generator::Index::midiKeyToModulatorEnvelopeHold);
}

constexpr Float midiKeyModulatorEnvelopeDecayAdjustment(const Generator::State& state) noexcept {
  return midiKeyEnvelopeScaling(state, Generator::Index::midiKeyToModulatorEnvelopeDecay);
}

Generator::Generator(size_t voiceIndex, const char* logTag) noexcept :
voiceIndex_{voiceIndex},
log_{os_log_create("SF2Lib", logTag)}
{
  ;
}

Generator::Generator(Float sampleRate, const char* logTag, size_t voiceIndex, Float delay, Float attack, Float hold, Float decay,
          int sustain, Float release) noexcept :
voiceIndex_{voiceIndex},
log_{os_log_create("SF2Lib", logTag)}
{
  sustainLevel_ = 1.0f - sustain / 1'000.0_F;
  stages_[StageIndex::delay].setDelay(int(round(sampleRate * delay)));
  stages_[StageIndex::attack].setAttack(int(round(sampleRate * attack)));
  stages_[StageIndex::hold].setHold(int(round(sampleRate * hold)));
  stages_[StageIndex::decay].setDecay(int(round(sampleRate * decay)), sustainLevel_);
  stages_[StageIndex::sustain].setSustain();
  stages_[StageIndex::release].setRelease(int(round(sampleRate * release)));

  os_log_debug(log_, "%zu delay: %d attack: %d / %f hold: %d decay: %d / %f sustain: %d / %f release %d / %f",
               voiceIndex_,
               stages_[StageIndex::delay].durationInSamples(),
               stages_[StageIndex::attack].durationInSamples(),
               stages_[StageIndex::attack].increment(),
               stages_[StageIndex::hold].durationInSamples(),
               stages_[StageIndex::decay].durationInSamples(),
               stages_[StageIndex::decay].increment(),
               sustain,
               sustainLevel_,
               stages_[StageIndex::release].durationInSamples(),
               stages_[StageIndex::release].increment());
}

void
Generator::gate(bool noteOn) noexcept
{
  if (noteOn) {
    os_log_debug(log_, "starting %zu", voiceIndex_);
    value_ = 0.0;
    enterStage(StageIndex::delay);
  } else if (stageIndex_ != StageIndex::idle) {
    os_log_debug(log_, "releasing %zu", voiceIndex_);
    enterStage(StageIndex::release);
  }
}

void
Generator::stop() noexcept
{
  stageIndex_ = StageIndex::idle;
  counter_ = 0;
  value_ = 0.0;
}

void
Generator::configureVolumeEnvelope(const State& state) noexcept
{
  /*
   Spec 8.1.2 sustainVolEnv

   This is the decrease in level, expressed in centibels, to which the Volume Envelope value ramps during the decay
   phase. For the Volume Envelope, the sustain level is best expressed in centibels of attenuation from full scale.
   A value of 0 indicates the sustain level is full level; this implies a zero duration of decay phase regardless of
   decay time. A positive value indicates a decay to the corresponding level. Values less than zero are to be
   interpreted as zero; conventionally 1000 indicates full attenuation. For example, a sustain level which
   corresponds to an absolute value 12dB below of peak would be 120.

   Our stages always work in normalized values, so convert centibels to an attenuation value.
   */
  auto sustainCents = state.modulated(Index::sustainVolumeEnvelope);
  sustainLevel_ = 1.0f - DSP::tenthPercentageToNormalized(sustainCents);

  auto delayTimecents = state.modulated(Index::delayVolumeEnvelope);
  stages_[StageIndex::delay].setDelay(sampleCountFor(state.sampleRate(),
                                                     delayTimecentsToSeconds(delayTimecents)));

  auto attackTimecents = state.modulated(Index::attackVolumeEnvelope);
  stages_[StageIndex::attack].setAttack(sampleCountFor(state.sampleRate(),
                                                       attackTimecentsToSeconds(attackTimecents)));

  auto holdTimecents = state.modulated(Index::holdVolumeEnvelope) + midiKeyVolumeEnvelopeHoldAdjustment(state);
  stages_[StageIndex::hold].setHold(sampleCountFor(state.sampleRate(),
                                                   holdTimecentsToSeconds(holdTimecents)));

  auto decayTimecents = state.modulated(Index::decayVolumeEnvelope) + midiKeyVolumeEnvelopeDecayAdjustment(state);
  stages_[StageIndex::decay].setDecay(sampleCountFor(state.sampleRate(),
                                                     decayTimecentsToSeconds(decayTimecents)),
                                      sustainLevel_);

  stages_[StageIndex::sustain].setSustain();

  auto releaseTimecents = state.modulated(Index::releaseVolumeEnvelope);
  stages_[StageIndex::release].setRelease(sampleCountFor(state.sampleRate(),
                                                         releaseTimecentsToSeconds(releaseTimecents)));

  os_log_debug(log_, "%zu - delay: %d attack: %d / %f hold: %d decay: %d / %f sustain: %f / %f release %d / %f",
               voiceIndex_,
               stages_[StageIndex::delay].durationInSamples(),
               stages_[StageIndex::attack].durationInSamples(),
               stages_[StageIndex::attack].increment(),
               stages_[StageIndex::hold].durationInSamples(),
               stages_[StageIndex::decay].durationInSamples(),
               stages_[StageIndex::decay].increment(),
               sustainCents,
               sustainLevel_,
               stages_[StageIndex::release].durationInSamples(),
               stages_[StageIndex::release].increment());

  gate(true);
}

void
Generator::configureModulationEnvelope(const State& state) noexcept
{
  /*
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
  auto sustainCents = state.modulated(Index::sustainModulatorEnvelope);
  sustainLevel_ = 1.0f - DSP::tenthPercentageToNormalized(sustainCents);

  auto delayTimecents = state.modulated(Index::delayModulatorEnvelope);
  stages_[StageIndex::delay].setDelay(sampleCountFor(state.sampleRate(),
                                                     delayTimecentsToSeconds(delayTimecents)));

  auto attackTimecents = state.modulated(Index::attackModulatorEnvelope);
  stages_[StageIndex::attack].setAttack(sampleCountFor(state.sampleRate(),
                                                       attackTimecentsToSeconds(attackTimecents)));

  auto holdTimecents = state.modulated(Index::holdModulatorEnvelope) + midiKeyModulatorEnvelopeHoldAdjustment(state);
  stages_[StageIndex::hold].setHold(sampleCountFor(state.sampleRate(),
                                                   holdTimecentsToSeconds(holdTimecents)));

  auto decayTimecents = state.modulated(Index::decayModulatorEnvelope) + midiKeyModulatorEnvelopeDecayAdjustment(state);
  stages_[StageIndex::decay].setDecay(sampleCountFor(state.sampleRate(),
                                                     decayTimecentsToSeconds(decayTimecents)),
                                      sustainLevel_);

  stages_[StageIndex::sustain].setSustain();

  auto releaseTimecents = state.modulated(Index::releaseModulatorEnvelope);
  stages_[StageIndex::release].setRelease(sampleCountFor(state.sampleRate(),
                                                         releaseTimecentsToSeconds(releaseTimecents)));

  os_log_debug(log_, "%zu - delay: %d attack: %d / %f hold: %d decay: %d / %f sustain: %f / %f release %d / %f",
               voiceIndex_,
               stages_[StageIndex::delay].durationInSamples(),
               stages_[StageIndex::attack].durationInSamples(),
               stages_[StageIndex::attack].increment(),
               stages_[StageIndex::hold].durationInSamples(),
               stages_[StageIndex::decay].durationInSamples(),
               stages_[StageIndex::decay].increment(),
               sustainCents,
               sustainLevel_,
               stages_[StageIndex::release].durationInSamples(),
               stages_[StageIndex::release].increment());

  gate(true);
}

