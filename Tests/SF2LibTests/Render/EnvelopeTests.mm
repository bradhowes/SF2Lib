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
  static Generator make(Float sampleRate, size_t voiceIndex, Float delay, Float attack, Float hold, Float decay,
                        int sustain, Float release) {
    return Generator(sampleRate, Generator::Kind::volume, voiceIndex, delay, attack, hold, decay, sustain, release);
  }
  static AUValue sustain(const Generator& gen) { return gen.sustain(); }
};
}

@interface EnvelopeTests : SamplePlayingTestCase

@end

@implementation EnvelopeTests

- (void)testGateOnOff {
  auto gen = Generator(48000.0, Generator::Kind::volume, 1);
  XCTAssertEqual(0.0, gen.value());
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue());
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertTrue(!gen.isGated());
  gen.gate(true);
  XCTAssertTrue(gen.isGated());
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue());
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertTrue(gen.isGated());
  gen.gate(false);
  XCTAssertTrue(!gen.isGated());
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testDelay {
  auto epsilon = 0.002;
  auto gen = EnvelopeTestInjector::make(1.0, 1, 3, 0, 0, 0, 0, 0);
  XCTAssertEqual(0.0, gen.value());
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue());
  gen.gate(true);
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testNoDelayNoAttack {
  auto epsilon = 0.002;
  auto gen = EnvelopeTestInjector::make(1.0, 1, 0, 0, 1, 0, 0, 0);
  gen.gate(true);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testAttackCurvature {
  auto epsilon = 0.001;
  auto gen = EnvelopeTestInjector::make(1.0, 1, 0, 10, 0, 0, 0, 0);
  gen.gate(true);
  XCTAssertEqual(0.0, gen.value());
  XCTAssertEqual(StageIndex::attack, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.01, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.04, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.09, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.16, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.25, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.36, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.49, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.64, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.81, gen.getNextValue(), epsilon);
  XCTAssertTrue(gen.isAttack());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue(), epsilon);
  XCTAssertFalse(gen.isAttack());
}

- (void)testHold {
  auto epsilon = 0.002;
  auto gen = EnvelopeTestInjector::make(1.0, 1, 0, 0, 3, 0, 200, 0);
  gen.gate(true);
  XCTAssertEqualWithAccuracy(1.0, gen.value(), epsilon);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.8, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testDecay {
  auto epsilon = 0.001;
  auto gen = EnvelopeTestInjector::make(1.0, 1, 0, 0, 0, 5, 500, 0);
  gen.gate(true);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.9, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.8, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.7, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.6, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.5, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  gen.gate(false);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testDecayAborted {
  auto epsilon = 0.001;
  auto gen = EnvelopeTestInjector::make(1.0, 1, 0, 0, 0, 5, 500, 0);
  gen.gate(true);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.9, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.8, gen.getNextValue(), epsilon);
  gen.gate(false);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue(), epsilon);
}

- (void)testSustain {
  auto gen = EnvelopeTestInjector::make(1.0, 1, 0, 0, 0, 0, 750, 0);
  gen.gate(true);
  XCTAssertEqual(0.25, gen.value());
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  XCTAssertEqual(0.25, gen.getNextValue());
  XCTAssertEqual(0.25, gen.getNextValue());
  gen.gate(false);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testRelease {
  auto epsilon = 0.001;
  auto gen = EnvelopeTestInjector::make(1.0, 1, 0, 0, 0, 0, 500, 5);
  gen.gate(true);
  XCTAssertEqual(0.5, gen.value());
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  gen.gate(false);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.4, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.3, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.2, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.1, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.000, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testVolumeEnvelopeSustainLevel {
  Float epsilon = 0.000001;
  State::State state{contexts.context2.makeState(0, 64, 32)};
  auto gen = Generator(state.sampleRate(), Generator::Kind::volume, 1);
  gen.configure(state);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 0);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(1.0, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 100);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.9, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 500);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.5, EnvelopeTestInjector::sustain(gen), epsilon);

  state.setValue(State::State::Index::sustainVolumeEnvelope, 900);
  gen.configure(state);
  XCTAssertEqualWithAccuracy(0.1, EnvelopeTestInjector::sustain(gen), epsilon);
}

- (void)testModulationEnvelopeSustainLevel {
  Float epsilon = 0.000001;
  State::State state{contexts.context2.makeState(0, 64, 32)};
  auto gen = Generator(state.sampleRate(), Generator::Kind::modulation, 1);
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
  auto gen = Generator(s1.sampleRate(), Generator::Kind::volume, 1);

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
