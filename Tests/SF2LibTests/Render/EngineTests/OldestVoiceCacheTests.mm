// Copyright © 2020 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SF2Lib/Render/Engine/OldestActiveVoiceCache.hpp"

using namespace SF2::Render::Engine;

@interface OldestVoiceCacheTests : XCTestCase

@end

@implementation OldestVoiceCacheTests

- (void)testCache {
  OldestActiveVoiceCache<96> cache{};
  XCTAssertTrue(cache.empty());
  XCTAssertEqual(cache.size(), 0);
  cache.add(0);
  XCTAssertFalse(cache.empty());
  XCTAssertEqual(cache.size(), 1);
  cache.add(1);
  XCTAssertEqual(cache.size(), 2);
  cache.remove(0);
  XCTAssertEqual(cache.size(), 1);
  XCTAssertFalse(cache.empty());
  XCTAssertEqual(1, cache.takeOldest());
  XCTAssertTrue(cache.empty());
  XCTAssertEqual(cache.size(), 0);
}

- (void)testLimits {
  OldestActiveVoiceCache<96> cache{};
  for (auto index = 0; index < 96; ++index) {
    cache.add(index);
  }
  XCTAssertEqual(cache.size(), 96);
}

- (void)testTiming {
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    OldestActiveVoiceCache<96> cache{};
    [self startMeasuring];
    for (auto iteration = 0; iteration < 100'000; ++iteration) {
      for (auto index = 0; index < 96; ++index) {
        cache.add(index);
      }
      while (!cache.empty()) {
        cache.takeOldest();
      }
    }
    [self stopMeasuring];
  }];
}

@end
