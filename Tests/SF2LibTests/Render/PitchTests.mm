// Copyright © 2020 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2File/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/LFO.hpp"
#include "SF2Lib/Render/Voice/Sample/Pitch.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Envelope;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Voice::Sample;

@interface PitchTests : SamplePlayingTestCase
@property (nonatomic) Float epsilon;
@property (nonatomic) MIDI::ChannelState* channelState;
@end

@implementation PitchTests

@synthesize epsilon;
@synthesize channelState;

- (void)setUp {
  self.epsilon = PresetTestContextBase::epsilonValue();
  self.channelState = new MIDI::ChannelState();
}

- (void)testUnity {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key));
  State::State state{sampleRate, key};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
}

- (void)testFractionalPitchModulationIsNotQuantized {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key));
  State::State state{sampleRate, key};
  self.sst.setValue(state, State::State::Index::vibratoLFOToPitch, 1);
  Pitch pitch{state};
  pitch.configure(header);

  auto increment = pitch.samplePhaseIncrement(ModLFO::Value(0_F), VibLFO::Value(0.25_F), Modulation::Value(0_F));
  XCTAssertEqualWithAccuracy(increment, std::exp2(0.25_F / 1200_F), 2.0e-7_F);
  XCTAssertNotEqual(increment, 1_F);
}

- (void)testFractionalPitchModulationChangesSmoothly {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key));
  State::State state{sampleRate, key};
  self.sst.setValue(state, State::State::Index::vibratoLFOToPitch, 1);
  Pitch pitch{state};
  pitch.configure(header);

  auto negative = pitch.samplePhaseIncrement(ModLFO::Value(0_F), VibLFO::Value(-0.25_F), Modulation::Value(0_F));
  auto zero = pitch.samplePhaseIncrement(ModLFO::Value(0_F), VibLFO::Value(0_F), Modulation::Value(0_F));
  auto positive = pitch.samplePhaseIncrement(ModLFO::Value(0_F), VibLFO::Value(0.25_F), Modulation::Value(0_F));
  XCTAssertLessThan(negative, zero);
  XCTAssertLessThan(zero, positive);
  XCTAssertEqualWithAccuracy(negative * positive, 1_F, 2.0e-7_F);
}

- (void)testNonOctaveSampleRateRatioIsExact {
  constexpr Float renderSampleRate = 44100_F;
  constexpr Float sourceSampleRate = 48000_F;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sourceSampleRate), uint8_t(key));
  State::State state{renderSampleRate, key};
  Pitch pitch{state};
  pitch.configure(header);

  auto increment = pitch.samplePhaseIncrement(ModLFO::Value(0_F), VibLFO::Value(0_F), Modulation::Value(0_F));
  XCTAssertEqualWithAccuracy(increment, sourceSampleRate / renderSampleRate, 2.0e-7_F);
}

- (void)test2x {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key));
  State::State state{sampleRate, key + 12};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
}

- (void)test4x {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key));
  State::State state{sampleRate, key + 24};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 4.0, self.epsilon);
}

- (void)testOverrideRoot {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key));
  State::State state{sampleRate, key};
  Pitch pitch{state};
  self.sst.setValue(state, State::State::Index::overridingRootKey, 81);
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, self.epsilon);
}

- (void)testGeneratorKey {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key));
  State::State state{sampleRate, key + 12};
  self.sst.setValue(state, State::State::Index::forcedMIDIKey, key);
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
}

- (void)testHalfSampleRate {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate * 2), uint8_t(key));
  State::State state{sampleRate, key};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
}

- (void)testDoubleSampleRate {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate / 2), uint8_t(key));
  State::State state{sampleRate, key};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, self.epsilon);
}

- (void)testPosPitchAdjustment {
  Float sampleRate = 44100.0;
  auto key = 69; // A4
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key), 100.0);
  State::State state{sampleRate, key - 1};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, 1.0e-3f);
}

- (void)testNegPitchAdjustment {
  Float sampleRate = 44100.0;
  auto key = 69; // A4
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key), -100.0);
  State::State state{sampleRate, key + 1};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
}

- (void)testScaleTuning {
  Float sampleRate = 44100.0;
  auto key = 69; // A4
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(sampleRate), uint8_t(key));
  State::State state{sampleRate, key + 1};
  Pitch pitch{state};
  // Make every key use the same frequency as the source key.
  self.sst.setValue(state, State::State::Index::scaleTuning, 0.0);
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);

  // Make keys play octaves above/below the sourceKey.
  self.sst.setValue(state, State::State::Index::scaleTuning, 1200.0);
  pitch.configure(header);

  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
}

- (void)testModLFOEffect {
  auto sourceKey = 69; // A4
  auto eventKey = sourceKey;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(44100.0), uint8_t(sourceKey));
  State::State state{44100.0, eventKey};
  Pitch pitch{state};
  pitch.configure(header);

  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);

  self.sst.setValue(state, State::State::Index::modulatorLFOToPitch, 1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(-1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, self.epsilon);

  self.sst.setValue(state, State::State::Index::modulatorLFOToPitch, -1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(-1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
}

- (void)testVibLFOEffect {
  auto sourceKey = 69; // A4
  auto eventKey = sourceKey;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(44100.0), uint8_t(sourceKey));
  State::State state{44100.0, eventKey};
  Pitch pitch{state};
  pitch.configure(header);

  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);

  self.sst.setValue(state, State::State::Index::vibratoLFOToPitch, 1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(1.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(-1.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, self.epsilon);

  self.sst.setValue(state, State::State::Index::vibratoLFOToPitch, -1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(1.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(-1.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
}

- (void)testModEnvEffect {
  auto sourceKey = 69; // A4
  auto eventKey = sourceKey;
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(44100.0), uint8_t(sourceKey));
  State::State state{44100.0, eventKey};
  Pitch pitch{state};
  pitch.configure(header);

  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);

  self.sst.setValue(state, State::State::Index::modulatorEnvelopeToPitch, 1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(1.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);

  self.sst.setValue(state, State::State::Index::modulatorEnvelopeToPitch, -1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(1.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
}

- (void)testConstantRootKey {
  Entity::SampleHeader header(0, 100, 80, 90, uint32_t(44100.0), uint8_t(255));
  State::State state{44100.0, 60};
  Pitch pitch{state};
  pitch.configure(header);

  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);

  self.sst.setValue(state, State::State::Index::modulatorEnvelopeToPitch, 1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(1.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);

  self.sst.setValue(state, State::State::Index::modulatorEnvelopeToPitch, -1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(1.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, self.epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, self.epsilon);
}


@end
