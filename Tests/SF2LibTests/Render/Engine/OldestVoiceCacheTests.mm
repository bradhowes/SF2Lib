// Copyright © 2020 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SF2Lib/Render/Engine/OldestVoiceCollection.hpp"

using namespace SF2::Render::Engine;

@interface OldestVoiceCacheTests : XCTestCase

@end

@implementation OldestVoiceCacheTests

- (void)testCache {
  OldestVoiceCollection<96> cache{3};
  XCTAssertTrue(cache.empty());
  XCTAssertEqual(cache.size(), 3);
  auto v1 = cache.voiceOn();
  XCTAssertEqual(v1, 0);
  XCTAssertFalse(cache.empty());
  XCTAssertEqual(cache.active(), 1);
  auto v2 = cache.voiceOn();
  XCTAssertEqual(v2, 1);
  XCTAssertEqual(cache.active(), 2);
  cache.voiceOff(v1);
  XCTAssertEqual(cache.active(), 1);
  XCTAssertFalse(cache.empty());
  cache.voiceOff(v2);
  XCTAssertTrue(cache.empty());
  XCTAssertEqual(cache.size(), 3);
}

static int countActive(const OldestVoiceCollection<96>& cache) noexcept {
  auto active = 0;
  for (auto _ : cache) ++active;
  XCTAssertEqual(cache.active(), active);
  return active;
}

- (void)testLimits {
  OldestVoiceCollection<96> cache{96};
  XCTAssertEqual(countActive(cache), 0);
  for (auto index = 0; index < 96; ++index) cache.voiceOn();
  XCTAssertEqual(countActive(cache), 96);
  for (auto index = 0; index < 96; ++index) cache.voiceOn();
  XCTAssertEqual(countActive(cache), 96);
  for (auto index = 0; index < 96; ++index) cache.voiceOn();
  XCTAssertEqual(countActive(cache), 96);

  for (auto index = 0; index < 96; index += 2) cache.voiceOff(index);
  XCTAssertEqual(countActive(cache), 48);
  for (auto index = 1; index < 96; index += 2) cache.voiceOff(index);
  XCTAssertEqual(countActive(cache), 0);
}

- (void)testRepetitions {
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    OldestVoiceCollection<96> cache{96};
    [self startMeasuring];
    for (auto iteration = 0; iteration < 50'000; ++iteration) {
      for (auto index = 0; index < 96; ++index) cache.voiceOn();
      for (auto index = 0; index < 96; ++index) cache.voiceOn();
      for (auto index = 96; index < 0; ++index) cache.voiceOff(index - 1);
    }
    [self stopMeasuring];
  }];
}

@end
