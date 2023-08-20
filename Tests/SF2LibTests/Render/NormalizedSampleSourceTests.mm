// Copyright © 2021 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>
#include <vector>

#include "../SampleBasedContexts.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/LFO.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"

using namespace SF2::Render;
using namespace SF2::Render::Envelope;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Voice::Sample;

@interface NormalizedSampleSourceTests : XCTestCase

@end

@implementation NormalizedSampleSourceTests {
  SampleBasedContexts* contexts;
  SF2::Float epsilon;
}

static SF2::Entity::SampleHeader header{0, 6, 3, 5, 100, 69, 0}; // 0: start, 1: end, 2: loop start, 3: loop end
static SF2::MIDI::ChannelState channelState;
static int16_t values[8] = {10000, -20000, 30000, 20000, 10000, -10000, -20000, -30000};

- (void)setUp {
  contexts = new SampleBasedContexts;
  epsilon = PresetTestContextBase::epsilonValue();
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


- (void)testLoadSamplesPerformance0 {
  const auto& file = contexts->context0.file();
  auto sampleEntries = file.sampleHeaders().size();
  XCTAssertEqual(sampleEntries, 495);

  [self measureBlock:^{
    for (size_t index = 0; index < sampleEntries; ++index) {
      auto samples = file.sampleSourceCollection()[index];
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
    }
  }];
}

@end

