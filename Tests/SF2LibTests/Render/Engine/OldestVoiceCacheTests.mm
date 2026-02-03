// Copyright © 2020 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SF2Lib/Render/Engine/OldestVoiceCollection.hpp"
#include "SF2Lib/Render/Engine/Traits.hpp"

using namespace SF2::Render::Engine;

@interface OldestVoiceCacheTests : XCTestCase

@end

@implementation OldestVoiceCacheTests

- (void)testCache {
  OldestVoiceCollection<96> cache{3};
  XCTAssertTrue(cache.empty());
  XCTAssertEqual(cache.size(), size_t(3));
  auto v1 = cache.voiceAcquire();
  XCTAssertEqual(v1, size_t(0));
  XCTAssertFalse(cache.empty());
  XCTAssertEqual(cache.active(), size_t(1));
  auto v2 = cache.voiceAcquire();
  XCTAssertEqual(v2, size_t(1));
  XCTAssertEqual(cache.active(), size_t(2));
  cache.voiceRelease(v1);
  XCTAssertEqual(cache.active(), size_t(1));
  XCTAssertFalse(cache.empty());
  cache.voiceRelease(v2);
  XCTAssertTrue(cache.empty());
  XCTAssertEqual(cache.size(), size_t(3));
}

static int countActive(const OldestVoiceCollection<traits::maxVoiceCount>& cache) noexcept {
  auto active = 0;
  for (auto _ : cache) ++active;
  XCTAssertEqual(cache.active(), size_t(active));
  return active;
}

- (void)testLimits {
  OldestVoiceCollection<traits::maxVoiceCount> cache{traits::maxVoiceCount};
  XCTAssertEqual(countActive(cache), 0);
  for (auto index = 0; index < traits::maxVoiceCount; ++index) cache.voiceAcquire();
  XCTAssertEqual(countActive(cache), traits::maxVoiceCount);
  for (auto index = 0; index < traits::maxVoiceCount; ++index) cache.voiceAcquire();
  XCTAssertEqual(countActive(cache), traits::maxVoiceCount);
  for (auto index = 0; index < traits::maxVoiceCount; ++index) cache.voiceAcquire();
  XCTAssertEqual(countActive(cache), traits::maxVoiceCount);

  for (auto index = 0; index < traits::maxVoiceCount; index += 2) cache.voiceRelease(size_t(index));
  XCTAssertEqual(countActive(cache), traits::maxVoiceCount / 2);
  for (auto index = 1; index < traits::maxVoiceCount; index += 2) cache.voiceRelease(size_t(index));
  XCTAssertEqual(countActive(cache), 0);
}

- (void)testRepetitions {
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    OldestVoiceCollection<traits::maxVoiceCount> cache{traits::maxVoiceCount};
    [self startMeasuring];
    for (auto iteration = 0; iteration < 5'000; ++iteration) {
      for (auto index = 0; index < traits::maxVoiceCount; ++index) cache.voiceAcquire();
      for (auto index = 0; index < traits::maxVoiceCount; ++index) cache.voiceAcquire();
      for (auto index = traits::maxVoiceCount; index < 0; --index) cache.voiceRelease(size_t(index - 1));
    }
    [self stopMeasuring];
  }];
}

@end
