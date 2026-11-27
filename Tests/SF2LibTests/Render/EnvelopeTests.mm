// Copyright © 2020 Brad Howes. All rights reserved.

#include <random>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"

#include "SF2Util/DSP.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/Envelope/Stage.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Envelope;

namespace SF2::Render::Envelope {

template <typename T>
concept EnvelopeGenerator = std::derived_from<T, SF2::Render::Envelope::Generator>;

struct EnvelopeTestInjector {
  static Volume DAHDSR(Float delay, Float attack, Float hold, Float decay, int sustain, Float release) {
    return Volume(1.0, delay, attack, hold, decay, sustain, release);
  }

  static Modulation modDAHDSR(Float delay, Float attack, Float hold, Float decay, int sustain, Float release) {
    return Modulation(1.0, delay, attack, hold, decay, sustain, release);
  }

  template <EnvelopeGenerator T>
  static Float sustain(const T& gen) { return gen.sustainLevel(); }
};
}

@interface EnvelopeTests : SamplePlayingTestCase
@end

/**
 Run two copies of the same envelope for `total` samples: one with `getNextValue`, the other with `fillBlock` in random
 block sizes from 1 to 64. At `releaseAt` the note is released (or aborted, if `abort`), between two blocks as in the
 engine. The values and the stages must match exactly.
 */
template <EnvelopeGenerator T>
static void checkFillBlockMatches(EnvelopeTests* self, T perSample, T blocked, std::mt19937& random, int total,
                                  int releaseAt, bool abort, NSString* label) {
  std::uniform_int_distribution<int> blockSizes(1, 64);
  perSample.start();
  blocked.start();
  int position = 0;
  bool released = false;
  while (position < total) {
    if (!released && position == releaseAt) {
      if (abort) { perSample.noteAborted(); blocked.noteAborted(); }
      else { perSample.noteReleased(); blocked.noteReleased(); }
      released = true;
    }
    int count = std::min(blockSizes(random), total - position);
    if (!released && releaseAt < position + count) count = releaseAt - position;
    Float values[64];
    StageIndex stages[64];
    if constexpr (std::is_same_v<T, Volume>) {
      blocked.fillBlock(values, stages, size_t(count));
    } else {
      blocked.fillBlock(values, size_t(count));
    }
    for (int index = 0; index < count; ++index) {
      auto expected = perSample.getNextValue().val;
      if (values[index] != expected) {
        XCTFail(@"%@: sample %d: %.9g != %.9g", label, position + index, values[index], expected);
        return;
      }
      if constexpr (std::is_same_v<T, Volume>) {
        if (stages[index] != perSample.activeIndex()) {
          XCTFail(@"%@: sample %d: stage %zu != %zu", label, position + index, size_t(stages[index]),
                  size_t(perSample.activeIndex()));
          return;
        }
      }
    }
    position += count;
    XCTAssertTrue(blocked.activeIndex() == perSample.activeIndex(), @"%@", label);
    XCTAssertEqual(blocked.counter(), perSample.counter(), @"%@", label);
  }
}

/**
 Configure `gen` from a voice state (the production path), with a 2 s release, and check `noteAborted` (exclusiveClass,
 SF2.01 8.1.2 #57). It must fade from the current value rather than jump to 0, and finish within about 5 ms, both when
 sustaining and when already in a (slow) release.
 */
template <EnvelopeGenerator T>
static void checkNoteAborted(EnvelopeTests* self, T& gen, State::State& state, State::State::Index release) {
  self.sst.setValue(state, release, 1200);
  gen.configure(state);
  const int abortSamples = int(std::round(state.sampleRate() * Generator::noteAbortReleaseDuration));
  XCTAssertGreaterThan(abortSamples, 100);

  auto samplesUntilIdle = [&]() {
    int count = 0;
    while (gen.isActive() && count < state.sampleRate()) {
      gen.getNextValue();
      ++count;
    }
    return count;
  };

  // Aborted while sustaining at full scale.
  gen.start();
  for (int index = 0; index < 1000; ++index) gen.getNextValue();
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.value().val, self.epsilon);
  gen.noteAborted();
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertGreaterThan(gen.getNextValue().val, 0.99);
  auto count = samplesUntilIdle();
  XCTAssertGreaterThan(count, abortSamples / 2);
  XCTAssertLessThanOrEqual(count, abortSamples + 2);

  // Aborted part way through a release that would otherwise take 2 seconds. `noteAborted` replaced the release stage, so
  // configure again, as `Voice::start` does for every note.
  gen.configure(state);
  gen.start();
  for (int index = 0; index < 1000; ++index) gen.getNextValue();
  gen.noteReleased();
  for (int index = 0; index < 100; ++index) gen.getNextValue();
  auto before = gen.value().val;
  XCTAssertGreaterThan(before, 0.9);
  gen.noteAborted();
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertGreaterThan(gen.getNextValue().val, before - 0.01);
  XCTAssertLessThanOrEqual(samplesUntilIdle(), abortSamples + 2);
}

@implementation EnvelopeTests

- (void)setUp {
  [super setUp];
  self.epsilon = PresetTestContextBase::epsilonValue();
}

- (void)testGateOnOff {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 2, 2, 1, 3);
  XCTAssertEqual(0.0, gen.value().val);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertTrue(!gen.isGated());
  gen.start();
  XCTAssertTrue(gen.isGated());
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqual(1.0, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertTrue(gen.isGated());
  gen.noteReleased();
  XCTAssertTrue(!gen.isGated());
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
}

- (void)testDelay {
  auto gen = EnvelopeTestInjector::DAHDSR(3, 0, 0, 0, 0, 0);
  XCTAssertEqual(0.0, gen.value().val);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue().val);
  gen.start();
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::attack, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testDelayAborted {
  auto gen = EnvelopeTestInjector::DAHDSR(3, 0, 0, 0, 0, 0);
  XCTAssertEqual(0.0, gen.value().val);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue().val);
  gen.start();
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
gen.noteReleased();
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testNoDelayNoAttack {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 1, 0, 0, 0);
  gen.start();
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testAttack {
  // SF2.01 8.1.2 #34: the volume envelope attack is "convex" so that the resulting gain is linear in amplitude. Each
  // value is the normalised-dB envelope value whose gain equals the progress through the attack.
  auto gen = EnvelopeTestInjector::DAHDSR(0, 10, 0, 0, 0, 0);
  gen.start();
  for (int step = 1; step <= 10; ++step) {
    auto value = gen.getNextValue().val;
    auto progress = step / 10.0;
    XCTAssertEqualWithAccuracy(value, volumeEnvelopeAttackCurve(Float(progress)), self.epsilon, @"step %d", step);
    // The gain the voice derives from this value (exact, without the 1 cB lookup table) is linear in the progress.
    auto gain = std::pow(10.0, -volumeEnvelopeToCentibels(value) / 200.0);
    XCTAssertEqualWithAccuracy(gain, progress, progress * 1.0e-5, @"step %d", step);
    if (step < 10) XCTAssertEqual(StageIndex::attack, gen.activeIndex());
  }
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
}

- (void)testAttackCurveShape {
  // Half way through the attack the gain is half of full scale (-6 dB), not -48 dB as with a linear-in-dB ramp.
  XCTAssertEqualWithAccuracy(volumeEnvelopeToCentibels(volumeEnvelopeAttackCurve(0.5_F)), 60.206, 0.001);
  XCTAssertEqual(volumeEnvelopeAttackCurve(0_F), 0_F);
  XCTAssertEqual(volumeEnvelopeAttackCurve(-1_F), 0_F);
  XCTAssertEqual(volumeEnvelopeAttackCurve(1_F), 1_F);
  // Below the 96 dB noise floor the curve is 0.
  XCTAssertEqual(volumeEnvelopeAttackCurve(1.0e-6_F), 0_F);
}

- (void)testModulationEnvelopeAttackStaysLinear {
  // The modulation envelope (gen 26) keeps a linear attack (see `Generator::enableConvexAttack`).
  auto gen = EnvelopeTestInjector::modDAHDSR(0, 10, 0, 0, 0, 0);
  gen.start();
  for (int step = 1; step <= 10; ++step) {
    XCTAssertEqualWithAccuracy(step / 10.0, gen.getNextValue().val, self.epsilon, @"step %d", step);
  }
}

- (void)testAttackAborted {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 10, 0, 0, 200, 3);
  gen.start();
  XCTAssertEqualWithAccuracy(volumeEnvelopeAttackCurve(0.1_F), gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(volumeEnvelopeAttackCurve(0.2_F), gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(volumeEnvelopeAttackCurve(0.3_F), gen.getNextValue().val, self.epsilon);
  auto atRelease = gen.getNextValue().val;
  XCTAssertEqualWithAccuracy(volumeEnvelopeAttackCurve(0.4_F), atRelease, self.epsilon);
  gen.noteReleased();
  XCTAssertFalse(gen.isAttack());
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  // The release starts from the shaped value actually being heard (gain 0.4), not from the raw attack progress, so
  // there is no jump in level.
  XCTAssertEqualWithAccuracy(atRelease - 1.0 / 3.0, gen.getNextValue().val, self.epsilon);
}

- (void)testHold {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 3, 0, 200, 0);
  gen.start();
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.8, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testDecay {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 0, 5, 500, 5);
  gen.start();
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.75, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  gen.noteReleased();
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.3, gen.getNextValue().val, self.epsilon);
}

- (void)testDecayAborted {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 0, 5, 500, 5);
  gen.start();
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.75, gen.getNextValue().val, self.epsilon);
  gen.noteReleased();
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.55, gen.getNextValue().val, self.epsilon);
}

- (void)testSustain {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 0, 0, 500, 0);
  gen.start();
  XCTAssertEqual(1, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqual(0.5, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqual(0.5, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqual(0.5, gen.getNextValue().val);
  gen.noteReleased();
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue().val);
}

- (void)testRelease {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 0, 0, 600, 5);
  gen.start();
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.4, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.4, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  gen.noteReleased();
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.2, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testVolumeEnvelopeNoteAborted {
  State::State state{self.contexts->context2.makeState(0, 64, 32)};
  auto gen = Volume();
  checkNoteAborted(self, gen, state, State::State::Index::releaseVolumeEnvelope);
}

- (void)testModulationEnvelopeNoteAborted {
  State::State state{self.contexts->context2.makeState(0, 64, 32)};
  auto gen = Modulation();
  checkNoteAborted(self, gen, state, State::State::Index::releaseModulatorEnvelope);
}

- (void)testVolumeEnvelopeSustainLevel {
  State::State state{self.contexts->context2.makeState(0, 64, 32)};
  auto gen = Volume();
  gen.configure(state);

  self.sst.setValue(state, State::State::Index::sustainVolumeEnvelope, 0);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(1.0, EnvelopeTestInjector::sustain(gen), self.epsilon);

  self.sst.setValue(state, State::State::Index::sustainVolumeEnvelope, 120);
  gen.configure(state);

  std::cout << std::setprecision(15) << EnvelopeTestInjector::sustain(gen) <<'\n';
  XCTAssertEqualWithAccuracy(1.0 - 120.0 / 960.0, EnvelopeTestInjector::sustain(gen), self.epsilon);

  self.sst.setValue(state, State::State::Index::sustainVolumeEnvelope, 500);
  gen.configure(state);
  std::cout << std::setprecision(15) << EnvelopeTestInjector::sustain(gen) <<'\n';
  XCTAssertEqualWithAccuracy(1.0 - 500.0 / 960.0, EnvelopeTestInjector::sustain(gen), self.epsilon);

  self.sst.setValue(state, State::State::Index::sustainVolumeEnvelope, 900);
  gen.configure(state);
  std::cout << std::setprecision(15) << EnvelopeTestInjector::sustain(gen) <<'\n';
  XCTAssertEqualWithAccuracy(1.0 - 900.0 / 960.0, EnvelopeTestInjector::sustain(gen), self.epsilon);

  self.sst.setValue(state, State::State::Index::sustainVolumeEnvelope, 960);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.0, EnvelopeTestInjector::sustain(gen), self.epsilon);

  self.sst.setValue(state, State::State::Index::sustainVolumeEnvelope, 1440);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.0, EnvelopeTestInjector::sustain(gen), self.epsilon);
}

- (void)testVolumeEnvelopeSustainRoundTripsThroughVoiceGainMapping {
  // The sustain level stored in the envelope must convert back to the generator's centibel value via the same mapping
  // the voice uses to compute gain.
  State::State state{self.contexts->context2.makeState(0, 64, 32)};
  auto gen = Volume();
  for (int centibels : {0, 60, 120, 480, 900}) {
    self.sst.setValue(state, State::State::Index::sustainVolumeEnvelope, centibels);
    gen.configure(state);
    XCTAssertEqualWithAccuracy(Float(centibels), volumeEnvelopeToCentibels(EnvelopeTestInjector::sustain(gen)),
                               self.epsilon);
  }
  XCTAssertEqualWithAccuracy(1.0, centibelsToVolumeEnvelope(-10.0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, centibelsToVolumeEnvelope(1'440.0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.251188643151, SF2::DSP::centibelsToAttenuation(volumeEnvelopeToCentibels(1.0 - 120.0 / 960.0)),
                             self.epsilon);
}

- (void)testModulationEnvelopeSustainLevel {
  State::State state{self.contexts->context2.makeState(0, 64, 32)};
  auto gen = Modulation();
  gen.configure(state);

  self.sst.setValue(state, State::State::Index::sustainModulatorEnvelope, 0);
  gen.configure(state);
  std::cout << std::setprecision(15) << EnvelopeTestInjector::sustain(gen) <<'\n';
  XCTAssertEqualWithAccuracy(1.0, EnvelopeTestInjector::sustain(gen), self.epsilon);

  self.sst.setValue(state, State::State::Index::sustainModulatorEnvelope, 100);
  gen.configure(state);
  std::cout << std::setprecision(15) << EnvelopeTestInjector::sustain(gen) <<'\n';
  XCTAssertEqualWithAccuracy(0.9, EnvelopeTestInjector::sustain(gen), self.epsilon);

  self.sst.setValue(state, State::State::Index::sustainModulatorEnvelope, 500);
  gen.configure(state);
  std::cout << std::setprecision(15) << EnvelopeTestInjector::sustain(gen) <<'\n';
  XCTAssertEqualWithAccuracy(0.5, EnvelopeTestInjector::sustain(gen), self.epsilon);

  self.sst.setValue(state, State::State::Index::sustainModulatorEnvelope, 900);
  gen.configure(state);
  std::cout << std::setprecision(15) << EnvelopeTestInjector::sustain(gen) <<'\n';
  XCTAssertEqualWithAccuracy(0.1, EnvelopeTestInjector::sustain(gen), self.epsilon);
}

- (void)testKeyToMod {
  auto s1 = self.contexts->context2.makeState(0, 60, 32);
  auto gen = Volume();

  // 1s hold duration
  self.sst.setValue(s1, State::State::Index::holdVolumeEnvelope, 0);
  gen.configure(s1);
  auto duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(s1.sampleRate(), duration, self.epsilon);

  // Track keyboard such that octave increase results in 0.5 x hold duration
  self.sst.setValue(s1, State::State::Index::midiKeyToVolumeEnvelopeHold, 100);
  // For key 60 there is no scaling so no adjustment to hold duration
  gen.configure(s1);
  duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(s1.sampleRate(), duration, self.epsilon);

  // An octave increase should halve the duration.
  auto s2 = self.contexts->context2.makeState(0, 72, 32);
  self.sst.setValue(s2, State::State::Index::holdVolumeEnvelope, 0);
  self.sst.setValue(s2, State::State::Index::midiKeyToVolumeEnvelopeHold, 100);
  gen.configure(s2);
  duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(s2.sampleRate() / 2.0, duration, self.epsilon);

  // An octave decrease should double the duration.
  auto s3 = self.contexts->context2.makeState(0, 48, 32);
  self.sst.setValue(s3, State::State::Index::holdVolumeEnvelope, 0);
  self.sst.setValue(s3, State::State::Index::midiKeyToVolumeEnvelopeHold, 100);
  gen.configure(s3);
  duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(s3.sampleRate() * 2.0, duration, self.epsilon);

  // Validate spec scenario
  auto s4 = self.contexts->context2.makeState(0, 36, 32);
  self.sst.setValue(s4, State::State::Index::midiKeyToVolumeEnvelopeHold, 50);
  self.sst.setValue(s4, State::State::Index::holdVolumeEnvelope, -7973);
  gen.configure(s4);
  duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(960, duration, 0.000001);
}

- (void)testFillBlockMatchesGetNextValue {
  // `fillBlock` (render path) must give exactly what per-sample `getNextValue` gives, for both envelope kinds, across
  // zero-length and long stages, releases and aborts at any point (including before the attack ends), ramps that
  // overshoot 1 or go below 0, and the idle tail.
  std::mt19937 random{20261127};
  std::uniform_int_distribution<int> shortStage(0, 6);
  std::uniform_int_distribution<int> longStage(0, 90);
  std::uniform_int_distribution<int> sustainLevel(0, 1000);
  std::uniform_int_distribution<int> releasePoint(0, 300);
  for (int trial = 0; trial < 400; ++trial) {
    Float delay = Float(shortStage(random));
    Float attack = Float(longStage(random));
    Float hold = Float(shortStage(random));
    Float decay = Float(longStage(random));
    int sustain = sustainLevel(random);
    Float release = Float(longStage(random));
    int releaseAt = releasePoint(random);
    bool abort = (trial % 3) == 0;
    auto label = [NSString stringWithFormat:@"trial %d (%g %g %g %g %d %g, release at %d%@)", trial, delay, attack,
                  hold, decay, sustain, release, releaseAt, abort ? @", aborted" : @""];
    checkFillBlockMatches(self, EnvelopeTestInjector::DAHDSR(delay, attack, hold, decay, sustain, release),
                          EnvelopeTestInjector::DAHDSR(delay, attack, hold, decay, sustain, release), random, 500,
                          releaseAt, abort, [@"volume " stringByAppendingString:label]);
    checkFillBlockMatches(self, EnvelopeTestInjector::modDAHDSR(delay, attack, hold, decay, sustain, release),
                          EnvelopeTestInjector::modDAHDSR(delay, attack, hold, decay, sustain, release), random, 500,
                          releaseAt, abort, [@"modulation " stringByAppendingString:label]);
  }
}

- (void)testFillBlockHoldsSustainWithoutTransitions {
  // The common case for a held note: a whole block in sustain is one fill, and the counter moves on by the block size.
  auto gen = EnvelopeTestInjector::DAHDSR(0, 1, 0, 1, 200, 10);
  gen.start();
  for (int index = 0; index < 4; ++index) gen.getNextValue();
  XCTAssertTrue(gen.activeIndex() == StageIndex::sustain);
  auto counter = gen.counter();
  auto level = gen.value().val;
  Float values[64];
  StageIndex stages[64];
  gen.fillBlock(values, stages, 64);
  for (int index = 0; index < 64; ++index) {
    XCTAssertEqual(values[index], level);
    XCTAssertTrue(stages[index] == StageIndex::sustain);
  }
  XCTAssertEqual(gen.counter(), counter - 64);
}

@end
