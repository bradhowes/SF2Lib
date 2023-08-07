// Copyright © 2020 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "../SampleBasedContexts.hpp"

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/Envelope/Stage.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Envelope;

namespace SF2::Render::Envelope {
struct EnvelopeTestInjector {
  static Volume DAHDSR(Float delay, Float attack, Float hold, Float decay, int sustain, Float release) {
    return Volume(1.0, 1, delay, attack, hold, decay, sustain, release);
  }
  template <typename T> static AUValue sustain(const T& gen) { return gen.sustainLevel(); }
};
}

@interface EnvelopeTests : SamplePlayingTestCase

@property Float epsilon;

@end

@implementation EnvelopeTests

- (void)setUp {
  self.epsilon = 1.0e-7;
}

- (void)testGateOnOff {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 2, 2, 1, 3);
  XCTAssertEqual(0.0, gen.value().val);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertTrue(!gen.isGated());
  gen.gate(true);
  XCTAssertTrue(gen.isGated());
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqual(1.0, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertTrue(gen.isGated());
  gen.gate(false);
  XCTAssertTrue(!gen.isGated());
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
}

- (void)testDelay {
  auto gen = EnvelopeTestInjector::DAHDSR(3, 0, 0, 0, 0, 0);
  XCTAssertEqual(0.0, gen.value().val);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue().val);
  gen.gate(true);
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testDelayAborted {
  auto gen = EnvelopeTestInjector::DAHDSR(3, 0, 0, 0, 0, 0);
  XCTAssertEqual(0.0, gen.value().val);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue().val);
  gen.gate(true);
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  gen.gate(false);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testNoDelayNoAttack {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 1, 0, 0, 0);
  gen.gate(true);
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testAttack {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 10, 0, 0, 0, 0);
  gen.gate(true);
  XCTAssertEqual(0.1, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::attack, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.2, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.3, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.4, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.6, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.7, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.8, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.9, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertFalse(gen.isAttack());
}

- (void)testAttackAborted {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 10, 0, 0, 200, 3);
  gen.gate(true);
  XCTAssertEqualWithAccuracy(0.1, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.2, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.3, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.4, gen.getNextValue().val, self.epsilon);
  gen.gate(false);
  XCTAssertFalse(gen.isAttack());
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.133333333333, gen.getNextValue().val, self.epsilon);
}

- (void)testHold {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 3, 0, 200, 0);
  gen.gate(true);
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.8, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testDecay {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 0, 5, 500, 5);
  gen.gate(true);
  XCTAssertEqualWithAccuracy(0.9, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.8, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.7, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.6, gen.getNextValue().val, self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.5, gen.getNextValue().val, self.epsilon);
  gen.gate(false);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.4, gen.getNextValue().val, self.epsilon);
}

- (void)testDecayAborted {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 0, 5, 500, 5);
  gen.gate(true);
  XCTAssertEqualWithAccuracy(0.9, gen.getNextValue().val, self.epsilon);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.8, gen.getNextValue().val, self.epsilon);
  gen.gate(false);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.7, gen.getNextValue().val, self.epsilon);
}

- (void)testSustain {
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 0, 0, 750, 0);
  gen.gate(true);
  XCTAssertEqual(0.25, gen.getNextValue().val);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqual(0.25, gen.getNextValue().val);
  XCTAssertEqual(0.25, gen.getNextValue().val);
  gen.gate(false);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
}

- (void)testRelease {
  auto epsilon = 0.001;
  auto gen = EnvelopeTestInjector::DAHDSR(0, 0, 0, 0, 500, 5);
  gen.gate(true);
  XCTAssertEqualWithAccuracy(0.5, gen.getNextValue().val, epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  gen.gate(false);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.4, gen.getNextValue().val, epsilon);
  XCTAssertEqualWithAccuracy(0.3, gen.getNextValue().val, epsilon);
  XCTAssertEqualWithAccuracy(0.2, gen.getNextValue().val, epsilon);
  XCTAssertEqualWithAccuracy(0.1, gen.getNextValue().val, epsilon);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue().val, epsilon);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testVolumeEnvelopeSustainLevel {
  Float epsilon = 0.000001;
  State::State state{contexts.context2.makeState(0, 64, 32)};
  auto gen = Volume(1);
  gen.configure(state);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 0);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(1.0, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 120);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.251189, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 500);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.003162, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 900);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.000032, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 960);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.000016, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 1440);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.000000, EnvelopeTestInjector::sustain(gen), epsilon);
}

- (void)testModulationEnvelopeSustainLevel {
  Float epsilon = 0.000001;
  State::State state{contexts.context2.makeState(0, 64, 32)};
  auto gen = Modulation(1);
  gen.configure(state);

  state.setValue(State::State::Index::sustainModulatorEnvelope, 0);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(1.0, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainModulatorEnvelope, 100);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.9, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainModulatorEnvelope, 500);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.5, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainModulatorEnvelope, 900);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.1, EnvelopeTestInjector::sustain(gen), epsilon);
}

- (void)testKeyToMod {
  Float epsilon = 0.000001;
  auto s1 = contexts.context2.makeState(0, 60, 32);
  auto gen = Volume(1);

  // 1s hold duration
  s1.setValue(State::State::Index::holdVolumeEnvelope, 0);
  gen.configure(s1);
  auto duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(s1.sampleRate(), duration, epsilon);

  // Track keyboard such that octave increase results in 0.5 x hold duration
  s1.setValue(State::State::Index::midiKeyToVolumeEnvelopeHold, 100);
  // For key 60 there is no scaling so no adjustment to hold duration
  gen.configure(s1);
  duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(s1.sampleRate(), duration, epsilon);

  // An octave increase should halve the duration.
  auto s2 = contexts.context2.makeState(0, 72, 32);
  s2.setValue(State::State::Index::holdVolumeEnvelope, 0);
  s2.setValue(State::State::Index::midiKeyToVolumeEnvelopeHold, 100);
  gen.configure(s2);
  duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(s2.sampleRate() / 2.0, duration, epsilon);

  // An octave decrease should double the duration.
  auto s3 = contexts.context2.makeState(0, 48, 32);
  s3.setValue(State::State::Index::holdVolumeEnvelope, 0);
  s3.setValue(State::State::Index::midiKeyToVolumeEnvelopeHold, 100);
  gen.configure(s3);
  duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(s3.sampleRate() * 2.0, duration, epsilon);

  // Validate spec scenario
  auto s4 = contexts.context2.makeState(0, 36, 32);
  s4.setValue(State::State::Index::midiKeyToVolumeEnvelopeHold, 50);
  s4.setValue(State::State::Index::holdVolumeEnvelope, -7973);
  gen.configure(s4);
  duration = gen.stage(StageIndex::hold).durationInSamples();
  XCTAssertEqualWithAccuracy(960, duration, 0.000001);
}

@end
