// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <iostream>
#include <vector>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.hpp"
#include "SF2Util/Base64.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"

using namespace SF2;
using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

@interface PerformanceTests : SamplePlayingTestCase
@end

@implementation PerformanceTests

- (void)setUp {
  [super setUp];
}

// Render 1 second of audio at 48000.0 sample rate using all voices of an engine and interpolating using 4th-order cubic.
// Uses both effects buffers to account for mixing effort when they are active.
//
// During development (debug) builds, this takes over 2s, but under -O3, it drops to 0.37s to render 128 voices at a time.

- (void)testEngineRenderPerformanceUsingCubic4thOrderInterpolation
{
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    auto harness{TestEngineHarness{}};
    // harness.setRenderingTimeBudgetScaling(-1.0);
    auto& engine{harness.engine()};
    harness.load(self.contexts->context0.path(), 0);

    int seconds = 1;
    auto mixer{harness.createMixer(seconds)};
    for (size_t voice = 0; voice < engine.maxVoiceCount(); ++voice) harness.sendNoteOn(uint8_t(12 + voice));

    [self startMeasuring];

    harness.renderToEnd(mixer);

    [self stopMeasuring];

    // [self playSamples: harness.dryBuffer() count: harness.duration()];
  }];
}

@end
