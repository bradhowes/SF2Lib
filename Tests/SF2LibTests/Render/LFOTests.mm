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
  static ModLFO makeMod(Float sampleRate, Float frequency, Float delay) { return ModLFO(sampleRate, frequency, delay); }
  static VibLFO makeVib(Float sampleRate, Float frequency, Float delay) { return VibLFO(sampleRate, frequency, delay); }

  ModLFO::Value delaySampleCount(ModLFO& lfo) const noexcept { return ModLFO::Value(lfo.delaySampleCount_); }
  ModLFO::Value increment(ModLFO& lfo) const noexcept { return ModLFO::Value(lfo.increment_); }

  VibLFO::Value delaySampleCount(VibLFO& lfo) const noexcept { return VibLFO::Value(lfo.delaySampleCount_); }
  VibLFO::Value increment(VibLFO& lfo) const noexcept { return VibLFO::Value(lfo.increment_); }
};
}

@interface LFOTests : SamplePlayingTestCase
@end

@implementation LFOTests

- (void)setUp {
  epsilon = PresetTestContextBase::epsilonValue();
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testSamples {
  auto osc = LFOTestInjector::makeMod(8.0, 1.0, 0.0);
  XCTAssertEqualWithAccuracy(osc.value().val, 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.value().val, 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.value().val, 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.value().val, 1.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.value().val, 1.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, 1.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, -0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, -1.0, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, -0.5, epsilon);
  XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
}

- (void)testDelay {
  {
    auto osc = LFOTestInjector::makeMod(8.0, 1.0, 0.125);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.5, epsilon);
  }
  {
    auto osc = LFOTestInjector::makeMod(8.0, 1.0, 0.25);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.5, epsilon);
  }
}

- (void)testConfig {
  {
    auto osc = LFOTestInjector::makeMod(8.0, 1.0, 0.125);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.5, epsilon);
  }
  {
    auto osc = LFOTestInjector::makeMod(8.0, 1.0, 0.0);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.5, epsilon);
  }
  {
    auto osc = LFOTestInjector::makeMod(8.0, 2.0, 0.0);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 1.0, epsilon);
  }
  {
    auto osc = LFOTestInjector::makeMod(8.0, 1.0, 0.0);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.0, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 0.5, epsilon);
    XCTAssertEqualWithAccuracy(osc.getNextValue().val, 1.0, epsilon);
  }
}

- (void)testConfigFromState {
  LFOTestInjector lti;
  State::State state{contexts.context2.makeState(0, 64, 32)};
  auto osc = VibLFO(state.sampleRate());

  sst.setValue(state, Generator::Index::delayVibratoLFO, -32768);
  sst.setValue(state, Generator::Index::frequencyVibratoLFO, 0);
  osc.configure(state);

  XCTAssertEqual(lti.delaySampleCount(osc).val, 0);
  XCTAssertEqualWithAccuracy(lti.increment(osc).val, 0.000681316576304, epsilon);

  sst.setValue(state, Generator::Index::delayVibratoLFO, -7972); // ~10 msec
  osc.configure(state);

  XCTAssertEqual(lti.delaySampleCount(osc).val, 480);
  sst.setValue(state, Generator::Index::delayVibratoLFO, 0);
}

@end
