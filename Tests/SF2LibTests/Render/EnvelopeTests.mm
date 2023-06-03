// Copyright © 2020 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "../SampleBasedContexts.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/Envelope/Stage.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Envelope;

namespace SF2::Render::Envelope {
struct EnvelopeTestInjector {
  static Generator make(Float sampleRate, Float delay, Float attack, Float hold, Float decay, Float sustain, Float release) {
    return Generator(sampleRate, Generator::Kind::gain, delay, attack, hold, decay, sustain, release);
  }
  static AUValue sustain(const Generator& gen) { return gen.sustain(); }
};
}

@interface EnvelopeTests : SamplePlayingTestCase

@end

@implementation EnvelopeTests

- (void)testGateOnOff {
  auto gen = Generator(48000.0, Generator::Kind::gain);
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
  auto gen = EnvelopeTestInjector::make(1.0, 3, 0, 0, 0, 1, 0);
  XCTAssertEqual(0.0, gen.value());
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue());
  gen.gate(true);
  XCTAssertEqual(StageIndex::delay, gen.activeIndex());
  XCTAssertEqual(0.0, gen.getNextValue());
  XCTAssertEqual(0.0, gen.getNextValue());
  XCTAssertEqual(1.0, gen.getNextValue());
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testNoDelayNoAttack {
  auto gen = EnvelopeTestInjector::make(1.0, 0, 0, 1, 0, 1, 0);
  gen.gate(true);
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertEqual(1.0, gen.getNextValue());
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testAttackCurvature {
  auto epsilon = 0.001;
  auto gen = EnvelopeTestInjector::make(1.0, 0, 10, 0, 0, 1, 0);
  gen.gate(true);
  XCTAssertEqual(0.0, gen.value());
  XCTAssertEqual(StageIndex::attack, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.373366868371, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.608711144270, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.757055662464, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.850561637888, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.909501243789, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.946652635751, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.970070266453, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.984831097710, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.994135290015, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(1.0, gen.getNextValue(), epsilon);
}

- (void)testHold {
  auto gen = EnvelopeTestInjector::make(1.0, 0, 0, 3, 0, 0.75, 0);
  gen.gate(true);
  XCTAssertEqual(1.0, gen.value());
  XCTAssertEqual(StageIndex::hold, gen.activeIndex());
  XCTAssertEqual(1.0, gen.getNextValue());
  XCTAssertEqual(1.0, gen.getNextValue());
  XCTAssertEqual(0.75, gen.getNextValue());
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
}

- (void)testDecay {
  auto epsilon = 0.001;
  auto gen = EnvelopeTestInjector::make(1.0, 0, 0, 0, 5, 0.5, 0);
  gen.gate(true);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.692631006359, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.570508479878, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.521987282938, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.502709049671, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.500, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  gen.gate(false);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testDecayAborted {
  auto epsilon = 0.001;
  auto gen = EnvelopeTestInjector::make(1.0, 0, 0, 0, 5, 0.5, 0);
  gen.gate(true);
  XCTAssertEqual(StageIndex::decay, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.692631006359, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.570508479878, gen.getNextValue(), epsilon);
  gen.gate(false);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.0, gen.getNextValue(), epsilon);
}

- (void)testSustain {
  auto gen = EnvelopeTestInjector::make(1.0, 0, 0, 0, 0, 0.25, 0);
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
  auto gen = EnvelopeTestInjector::make(1.0, 0, 0, 0, 0, 0.5, 5);
  gen.gate(true);
  XCTAssertEqual(0.5, gen.value());
  XCTAssertEqual(StageIndex::sustain, gen.activeIndex());
  gen.gate(false);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.192631006359, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.0705084798785, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.0219872829376, gen.getNextValue(), epsilon);
  XCTAssertEqualWithAccuracy(0.00270904967126, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::release, gen.activeIndex());
  XCTAssertEqualWithAccuracy(0.000, gen.getNextValue(), epsilon);
  XCTAssertEqual(StageIndex::idle, gen.activeIndex());
}

- (void)testEnvelopeSustainLevel {
  Float epsilon = 0.000001;
  State::State state{contexts.context2.makeState(0, 64, 32)};
  auto gen = Generator(state.sampleRate(), Generator::Kind::modulator);
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

- (void)testKeyToMod {
  Float epsilon = 0.000001;
  auto s1 = contexts.context2.makeState(0, 60, 32);
  auto gen = Generator(s1.sampleRate(), Generator::Kind::modulator);

  // 1s hold duration
  s1.setValue(State::State::Index::holdVolumeEnvelope, 0);
  // Track keyboard such that octave increase results in 0.5 x hold duration
  s1.setValue(State::State::Index::midiKeyToVolumeEnvelopeHold, 100);
  // For key 60 there is no scaling so no adjustment to hold duration
  gen.configure(s1);
  auto duration = gen.stage(StageIndex::hold).durationInSamples();
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
