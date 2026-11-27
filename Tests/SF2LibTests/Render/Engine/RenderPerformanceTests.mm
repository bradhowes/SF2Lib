// Copyright © 2026 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

using namespace SF2;

// §6 item 2: cost of rendering many sustained voices. Only meaningful in an optimised build, e.g.
// `swift test -c release --filter RenderPerformanceTests`.

static constexpr AUAudioFrameCount renderFrames = 48'000;
static constexpr uint8_t voiceCount = 32;

@interface RenderPerformanceTests : XCTestCase
@end

@implementation RenderPerformanceTests

- (void)testRender32VoicesForOneSecond {
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibRenderPerformance.sf2";
  SF2Builder::minimal().writeTo(path);
  [self measureBlock:^{
    auto harness{TestEngineHarness{48000.0}};
    harness.load(path, 0);
    auto mixer{harness.createMixer(double(renderFrames) / 48000.0)};
    for (uint8_t key = 0; key < voiceCount; ++key) harness.sendNoteOn(uint8_t(40 + key), 127);
    harness.renderToEnd(mixer);
    XCTAssertEqual(harness.engine().activeVoiceCount(), size_t(voiceCount));
  }];
}

- (void)testRender32VoicesInALongAttack {
  // Every voice stays in a 2 s volume attack (1200 timecents) for the whole second rendered.
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibRenderPerformance.sf2";
  SF2Builder::minimal().writeTo(path);
  [self measureBlock:^{
    auto harness{TestEngineHarness{48000.0}};
    harness.load(path, 0);
    harness.setParameter(SF2::Entity::Generator::Index::attackVolumeEnvelope, 1'200);
    auto mixer{harness.createMixer(double(renderFrames) / 48000.0)};
    for (uint8_t key = 0; key < voiceCount; ++key) harness.sendNoteOn(uint8_t(40 + key), 127);
    harness.renderToEnd(mixer);
    XCTAssertEqual(harness.engine().activeVoiceCount(), size_t(voiceCount));
  }];
}

@end
