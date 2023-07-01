// Copyright © 2021 Brad Howes. All rights reserved.

#include <vector>

#include "../SampleBasedContexts.hpp"

#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/LFO.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2::Entity;
using namespace SF2::Render;
using namespace SF2::Render::Voice;

namespace SF2::Render {
struct LFOTestInjector {
  static LFO make(Float sampleRate, Float frequency, Float delay) {
    return LFO(sampleRate, LFO::Kind::modulator, frequency, delay);
  }

  Float delaySampleCount(LFO& lfo) const { return lfo.delaySampleCount_; }
  Float increment(LFO& lfo) const noexcept { return lfo.increment_; }
};
}

@interface LFOTests : XCTestCase
@end

@implementation LFOTests {
  SampleBasedContexts contexts;
  SF2::Float epsilon;
}

- (void)setUp {
  epsilon = 1.0e-8f;
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testSamples {
  auto osc = LFOTestInjector::make(8.0, 1.0, 0.0);
  XCTAssertEqualWithAccuracy(osc.value(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.value(), 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.value(), 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.value(), 1.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.value(), 1.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 1.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), -0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), -1.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), -0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
}

- (void)testDelay {
  auto osc = LFOTestInjector::make(8.0, 1.0, 0.125);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.5, epsilon);
  osc = LFOTestInjector::make(8.0, 1.0, 0.25);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.5, epsilon);
}

- (void)testConfig {
  auto osc = LFOTestInjector::make(8.0, 1.0, 0.125);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.5, epsilon);
  osc = LFOTestInjector::make(8.0, 1.0, 0.0);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.5, epsilon);
  osc = LFOTestInjector::make(8.0, 2.0, 0.0);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 1.0, epsilon);
  osc = LFOTestInjector::make(8.0, 1.0, 0.0);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue(), 1.0, epsilon);
}

- (void)testConfigFromState {
  LFOTestInjector lti;
  State::State state{contexts.context2.makeState(0, 64, 32)};
  auto osc = LFO(state.sampleRate(), LFO::Kind::vibrato);

  state.setValue(Generator::Index::delayVibratoLFO, -32768);
  state.setValue(Generator::Index::frequencyVibratoLFO, 0);
  osc.configure(state);
  XCTAssertEqual(lti.delaySampleCount(osc), 0);
  XCTAssertEqualWithAccuracy(lti.increment(osc), 0.000681316576304, epsilon);

  state.setValue(Generator::Index::delayVibratoLFO, -7972); // ~10 msec
  osc.configure(state);
  XCTAssertEqual(lti.delaySampleCount(osc), 480);
  state.setValue(Generator::Index::delayVibratoLFO, 0);
}

@end
