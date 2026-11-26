// Copyright © 2026 Brad Howes. All rights reserved.

#include <functional>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"
#include "SF2Util/Timer.hpp"

using namespace SF2;
using LoadResponse = SF2::IO::File::LoadResponse;

// §6 item 9: the render time budget. A fake clock advances by `fakeStep` nanoseconds on every call, which makes budget
// overruns deterministic.
static uint64_t fakeNow = 0;
static uint64_t fakeStep = 0;
static uint64_t fakeClock() noexcept { return fakeNow += fakeStep; }

static constexpr AUAudioFrameCount sliceFrames = 512;

/// The SF2Builder sine: one looping sample, so every note sustains at a steady level.
static std::string sinePath()
{
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibRenderBudget.sf2";
  SF2Builder::minimal().writeTo(path);
  return path;
}

/**
 Play `keys` in order, render a 512-frame warm-up slice without a budget, call `configure`, then render `frames` more.

 @param keys the notes to play, oldest first
 @param configure called after the warm-up slice, e.g. to turn on the budget
 @param frames the number of frames to render after `configure`
 @param check called at the end with the harness, e.g. to look at the voices
 @returns the left channel of the frames rendered after `configure`
 */
static std::vector<AUValue> renderAfterWarmUp(const std::vector<uint8_t>& keys,
                                              std::function<void(TestEngineHarness&)> configure,
                                              AUAudioFrameCount frames = sliceFrames,
                                              std::function<void(TestEngineHarness&)> check = nullptr)
{
  auto harness{TestEngineHarness{48000.0}};
  harness.load(sinePath(), 0);
  auto mixer{harness.createMixer(double(sliceFrames + frames) / 48000.0)};
  for (auto key : keys) harness.sendNoteOn(key, 127);
  harness.renderForCount(mixer, sliceFrames);
  if (configure) configure(harness);
  harness.renderForCount(mixer, frames);
  if (check) check(harness);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data + sliceFrames, data + sliceFrames + frames);
}

static size_t activeVoices(TestEngineHarness& harness) { return harness.engine().activeVoiceCount(); }

@interface RenderBudgetTests : XCTestCase
@end

@implementation RenderBudgetTests

- (void)testOverrunFadesOutRemainingVoicesInsteadOfCuttingThem {
  // The budget runs out after the two newest voices. The two oldest used to be stopped outright (a step to 0 in the
  // output); now each is faded out linearly over `budgetFadeOutFrames` frames and then stopped.
  std::vector<uint8_t> keys{60, 64, 67, 72};
  size_t remaining = 0;
  auto budgeted = renderAfterWarmUp(keys, [](TestEngineHarness& harness) {
    // Budget for the slice is sliceFrames * frameNanoseconds. Voice checks see 1, 2, 3, 4 steps elapsed, so with a
    // step of 2/5 of the budget the third voice (64) is the first to find the budget used up.
    fakeNow = 0;
    fakeStep = sliceFrames * harness.frameNanoseconds() * 2 / 5;
    harness.enableRenderingBudget(1.0, &fakeClock);
  }, sliceFrames, [&remaining](TestEngineHarness& harness) { remaining = activeVoices(harness); });
  XCTAssertEqual(remaining, size_t(2));

  // Voices are independent, so the expected output is the sum of each note rendered on its own.
  std::map<uint8_t, std::vector<AUValue>> alone;
  for (auto key : keys) alone[key] = renderAfterWarmUp({key}, nullptr);

  auto fadeFrames = Render::Engine::Engine::budgetFadeOutFrames;
  double oldestLevel = 0.0;
  for (size_t index = 0; index < sliceFrames; ++index) {
    double gain = index < fadeFrames ? double(fadeFrames - index - 1) / double(fadeFrames) : 0.0;
    double faded = double(alone[60][index]) + double(alone[64][index]);
    double expected = double(alone[72][index]) + double(alone[67][index]) + gain * faded;
    XCTAssertEqualWithAccuracy(budgeted[index], expected, 1.0e-5, @"frame %zu", index);
    if (index < 8) oldestLevel = std::max(oldestLevel, std::abs(faded));
  }
  // Guard against a vacuous test: the faded voices were loud at the start of the slice, so cutting them would show.
  XCTAssertGreaterThan(oldestLevel, 0.05);
}

- (void)testPredictedOverrunFastReleasesOldestVoices {
  // With a running cost estimate that fits only two voices, the two oldest get a fast (5 ms) release before rendering.
  // They keep sounding (fading) at first, then finish; the two newest are untouched.
  std::vector<uint8_t> keys{60, 64, 67, 72};
  size_t activeEarly = 0;
  size_t fastReleasingEarly = 0;
  std::set<int> fastReleasedKeys;
  auto shed = renderAfterWarmUp(keys, [](TestEngineHarness& harness) {
    fakeNow = 0;
    fakeStep = 0;  // time never advances, so the mid-slice overrun check never fires
    harness.enableRenderingBudget(1.0, &fakeClock);
    // Cost of one voice for a whole slice = budget / 2.5, so 2 voices fit.
    harness.setAverageVoiceFrameNanoseconds(double(harness.frameNanoseconds()) / 2.5);
  }, 48, [&](TestEngineHarness& harness) {
    activeEarly = activeVoices(harness);
    for (size_t index = 0; index < Render::Engine::traits::maxVoiceCount; ++index) {
      auto& voice = harness.voice(index);
      if (voice.isActive() && voice.isFastReleasing()) {
        ++fastReleasingEarly;
        fastReleasedKeys.insert(voice.initiatingKey());
      }
    }
  });
  XCTAssertEqual(activeEarly, size_t(4));      // still fading after 1 ms
  XCTAssertEqual(fastReleasingEarly, size_t(2));
  XCTAssertTrue((fastReleasedKeys == std::set<int>{60, 64}));

  // No step at the start of the slice: the first sample matches the unshed output closely.
  auto unshed = renderAfterWarmUp(keys, nullptr, 48);
  XCTAssertEqualWithAccuracy(shed[0], unshed[0], 0.01);
  XCTAssertFalse(shed == unshed);

  // After 10 ms the fast-released voices are gone and only the two newest remain.
  size_t activeLater = 0;
  renderAfterWarmUp(keys, [](TestEngineHarness& harness) {
    fakeNow = 0;
    fakeStep = 0;
    harness.enableRenderingBudget(1.0, &fakeClock);
    harness.setAverageVoiceFrameNanoseconds(double(harness.frameNanoseconds()) / 2.5);
  }, 480, [&activeLater](TestEngineHarness& harness) { activeLater = activeVoices(harness); });
  XCTAssertEqual(activeLater, size_t(2));
}

- (void)testNoSheddingWithinBudget {
  // When the voices fit, the budgeted output is identical to the unbudgeted one, and the cost estimate is maintained.
  std::vector<uint8_t> keys{60, 64, 67, 72};
  double average = 0.0;
  auto budgeted = renderAfterWarmUp(keys, [](TestEngineHarness& harness) {
    fakeNow = 0;
    fakeStep = 1;
    harness.enableRenderingBudget(1.0, &fakeClock);
  }, sliceFrames * 4, [&average](TestEngineHarness& harness) { average = harness.averageVoiceFrameNanoseconds(); });
  auto unbudgeted = renderAfterWarmUp(keys, nullptr, sliceFrames * 4);
  XCTAssertTrue(budgeted == unbudgeted);
  XCTAssertGreaterThan(average, 0.0);
}

- (void)testHarnessRendersWithoutABudget {
  // Rendering tests compare against hard-coded samples, so the harness must not use the wall-clock budget: under load
  // it sheds or fades voices. The engine's own default (1.0) is for real use. (The harness lost its `-1.0` when the
  // engine constructor stopped taking the scaling, which made multi-voice tests such as
  // `testEngineParameterControlChangeForPanning` fail now and then.)
  auto harness{TestEngineHarness{}};
  XCTAssertLessThanOrEqual(harness.engine().renderingTimeBudgetScaling(), 0.0);
  XCTAssertGreaterThan(SF2::Render::Engine::Engine().renderingTimeBudgetScaling(), 0.0);
}

- (void)testTimerIsMonotonic {
  // CLOCK_REALTIME could jump backwards (NTP), making `now() - then` wrap around.
  auto last = Utils::Timer::now();
  for (int count = 0; count < 100'000; ++count) {
    auto now = Utils::Timer::now();
    XCTAssertGreaterThanOrEqual(now, last);
    last = now;
  }
}

@end
