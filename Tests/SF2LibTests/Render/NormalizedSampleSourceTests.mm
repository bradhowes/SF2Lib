// Copyright © 2021 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>
#include <vector>

#include "../SampleBasedContexts.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"

using namespace SF2::Render::Voice;
using namespace SF2::Render::Voice::Sample;

@interface NormalizedSampleSourceTests : XCTestCase

@end

@implementation NormalizedSampleSourceTests {
  SampleBasedContexts* contexts;
}

static SF2::Entity::SampleHeader header{0, 6, 3, 5, 100, 69, 0}; // 0: start, 1: end, 2: loop start, 3: loop end
static SF2::MIDI::ChannelState channelState;
static int16_t values[8] = {10000, -20000, 30000, 20000, 10000, -10000, -20000, -30000};
static SF2::Float epsilon = 1e-6;

- (void)setUp {
  contexts = new SampleBasedContexts;
}

- (void)tearDown {
  delete contexts;
}

- (void)testLoad {
  NormalizedSampleSource source{values, header};
  XCTAssertEqual(source.size(), 0);
  XCTAssertFalse(source.isLoaded());
  XCTAssertEqual(0, source.header().startIndex());
  XCTAssertEqual(6, source.header().endIndex());

  source.load();

  XCTAssertTrue(source.isLoaded());
  XCTAssertEqual(source.size(), source.header().endIndex() + NormalizedSampleSource::sizePaddingAfterEnd);
  XCTAssertEqual(source[0], values[0] * NormalizedSampleSource::normalizationScale);
  XCTAssertEqual(source[1], values[1] * NormalizedSampleSource::normalizationScale);
}

- (void)testUnload {
  NormalizedSampleSource source{values, header};
  source.load();
  XCTAssertTrue(source.isLoaded());
  source.unload();
  XCTAssertFalse(source.isLoaded());
  XCTAssertEqual(source.size(), 0);
}


- (void)testLinearInterpolation {
  State::State state{100, channelState};
  Sample::Generator gen{Sample::Generator::Interpolator::linear};
  NormalizedSampleSource source{values, header};
  source.load();
  gen.configure(source, state);
  Sample::Pitch pitch{state};
  pitch.configure(source.header());
  auto inc = pitch.samplePhaseIncrement(0.0, 0.0, 0.0);
  XCTAssertEqualWithAccuracy(0.30517578125, gen.generate(inc, true), 0.0000001);
  XCTAssertEqualWithAccuracy(0.288164037013, gen.generate(inc, true), epsilon);
  XCTAssertEqualWithAccuracy(0.271152292776, gen.generate(inc, true), epsilon);
  XCTAssertEqualWithAccuracy(0.254140548539, gen.generate(inc, true), epsilon);
}

- (void)testLoadSamplesPerformance0 {
  const auto& file = contexts->context0.file();
  auto sampleEntries = file.sampleHeaders().size();
  XCTAssertEqual(sampleEntries, 495);

  [self measureBlock:^{
    for (size_t index = 0; index < sampleEntries; ++index) {
      auto samples = file.sampleSourceCollection()[index];
      samples.load();
      samples.unload();
    }
  }];
}

- (void)testLoadSamplesPerformance1 {
  const auto& file = contexts->context1.file();
  auto sampleEntries = file.sampleHeaders().size();
  XCTAssertEqual(sampleEntries, 864);

  [self measureBlock:^{
    for (size_t index = 0; index < sampleEntries; ++index) {
      auto samples = file.sampleSourceCollection()[index];
      samples.load();
      samples.unload();
    }
  }];
}

- (void)testLoadSamplesPerformance2 {
  const auto& file = contexts->context2.file();
  auto sampleEntries = file.sampleHeaders().size();
  XCTAssertEqual(sampleEntries, 24);

  [self measureBlock:^{
    for (size_t index = 0; index < sampleEntries; ++index) {
      auto samples = file.sampleSourceCollection()[index];
      samples.load();
      samples.unload();
    }
  }];
}

@end

