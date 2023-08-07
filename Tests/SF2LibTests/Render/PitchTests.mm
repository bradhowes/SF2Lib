// Copyright © 2020 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "../SampleBasedContexts.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/LFO.hpp"
#include "SF2Lib/Render/Voice/Sample/Pitch.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Envelope;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Voice::Sample;

@interface PitchTests : XCTestCase
@end

@implementation PitchTests {
  Float epsilon;
  MIDI::ChannelState channelState;
}

- (void)setUp {
  epsilon = PresetTestContextBase::epsilonValue();
}

- (void)testUnity {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate, key);
  State::State state{sampleRate, channelState, key};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);
}

- (void)test2x {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate, key);
  State::State state{sampleRate, channelState, key + 12};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, epsilon);
}

- (void)test4x {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate, key);
  State::State state{sampleRate, channelState, key + 24};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 4.0, epsilon);
}

- (void)testOverrideRoot {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate, key);
  State::State state{sampleRate, channelState, key};
  Pitch pitch{state};
  state.setValue(State::State::Index::overridingRootKey, 81);
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, epsilon);
}

- (void)testGeneratorKey {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate, key);
  State::State state{sampleRate, channelState, key + 12};
  state.setValue(State::State::Index::forcedMIDIKey, key);
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);
}

- (void)testHalfSampleRate {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate * 2, key);
  State::State state{sampleRate, channelState, key};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, epsilon);
}

- (void)testDoubleSampleRate {
  Float sampleRate = 44100.0;
  auto key = 69;
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate / 2, key);
  State::State state{sampleRate, channelState, key};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, epsilon);
}

- (void)testPosPitchAdjustment {
  Float sampleRate = 44100.0;
  auto key = 69; // A4
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate, key, 100.0);
  State::State state{sampleRate, channelState, key - 1};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, 1.0e-3f);
}

- (void)testNegPitchAdjustment {
  Float sampleRate = 44100.0;
  auto key = 69; // A4
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate, key, -100.0);
  State::State state{sampleRate, channelState, key + 1};
  Pitch pitch{state};
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);
}

- (void)testScaleTuning {
  Float sampleRate = 44100.0;
  auto key = 69; // A4
  Entity::SampleHeader header(0, 100, 80, 90, sampleRate, key);
  State::State state{sampleRate, channelState, key + 1};
  Pitch pitch{state};
  // Make every key use the same frequency as the source key.
  state.setValue(State::State::Index::scaleTuning, 0.0);
  pitch.configure(header);
  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);

  // Make keys play octaves above/below the sourceKey.
  state.setValue(State::State::Index::scaleTuning, 1200.0);
  pitch.configure(header);

  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, epsilon);
}

- (void)testModLFOEffect {
  auto sourceKey = 69; // A4
  auto eventKey = sourceKey;
  Entity::SampleHeader header(0, 100, 80, 90, 44100.0, sourceKey);
  State::State state{44100.0, channelState, eventKey};
  Pitch pitch{state};
  pitch.configure(header);

  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);

  state.setValue(State::State::Index::modulatorLFOToPitch, 1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(-1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, epsilon);

  state.setValue(State::State::Index::modulatorLFOToPitch, -1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(-1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, epsilon);
}

- (void)testVibLFOEffect {
  auto sourceKey = 69; // A4
  auto eventKey = sourceKey;
  Entity::SampleHeader header(0, 100, 80, 90, 44100.0, sourceKey);
  State::State state{44100.0, channelState, eventKey};
  Pitch pitch{state};
  pitch.configure(header);

  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);

  state.setValue(State::State::Index::vibratoLFOToPitch, 1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(1.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(-1.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, epsilon);

  state.setValue(State::State::Index::vibratoLFOToPitch, -1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(1.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(-1.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, epsilon);
}

- (void)testModEnvEffect {
  auto sourceKey = 69; // A4
  auto eventKey = sourceKey;
  Entity::SampleHeader header(0, 100, 80, 90, 44100.0, sourceKey);
  State::State state{44100.0, channelState, eventKey};
  Pitch pitch{state};
  pitch.configure(header);

  auto inc = pitch.samplePhaseIncrement(ModLFO::Value(1.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);

  state.setValue(State::State::Index::modulatorEnvelopeToPitch, 1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(1.0));
  XCTAssertEqualWithAccuracy(inc, 2.0, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);

  state.setValue(State::State::Index::modulatorEnvelopeToPitch, -1200);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(1.0));
  XCTAssertEqualWithAccuracy(inc, 0.5, epsilon);
  inc = pitch.samplePhaseIncrement(ModLFO::Value(0.0), VibLFO::Value(0.0), Modulation::Value(0.0));
  XCTAssertEqualWithAccuracy(inc, 1.0, epsilon);
}

@end
