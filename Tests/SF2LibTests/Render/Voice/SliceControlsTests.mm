// Copyright © 2026 Brad Howes. All rights reserved.

#include <array>
#include <functional>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

using namespace SF2;
using Index = SF2::Entity::Generator::Index;

// §6 item 2: `Voice::renderFrames` captures pan, sends, attenuation, the filter inputs and the pitch values once per
// render slice. These tests check that a change between two slices is used from the first frame of the next slice,
// i.e. nothing captured for one slice leaks into the next.

static constexpr AUAudioFrameCount warmUpFrames = 512;
static constexpr AUAudioFrameCount changeFrame = 100;
static constexpr AUAudioFrameCount afterFrames = 412;
static constexpr AUAudioFrameCount totalFrames = warmUpFrames + changeFrame + afterFrames;

/// The left, right and chorus channels of a render.
struct Channels {
  std::vector<AUValue> left;
  std::vector<AUValue> right;
  std::vector<AUValue> chorus;
};

static std::string sinePath()
{
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibSliceControls.sf2";
  SF2Builder::minimal().writeTo(path);
  return path;
}

/**
 Play one note, render `warmUpFrames + changeFrame` frames, call `change` (if given), then render `afterFrames` more.
 Each render call is one or more `Engine::renderInto` slices, so `change` falls between two slices.
 */
static Channels render(std::function<void(TestEngineHarness&)> change)
{
  auto harness{TestEngineHarness{48000.0}};
  harness.load(sinePath(), 0);
  auto mixer{harness.createMixer(double(totalFrames) / 48000.0)};
  harness.sendNoteOn(69, 127);
  harness.renderForCount(mixer, warmUpFrames + changeFrame);
  if (change) change(harness);
  harness.renderForCount(mixer, afterFrames);
  auto channel = [](AVAudioPCMBuffer* buffer, size_t index) {
    const AUValue* data = buffer.floatChannelData[index];
    return std::vector<AUValue>(data, data + totalFrames);
  };
  return {channel(harness.dryBuffer(), 0), channel(harness.dryBuffer(), 1), channel(harness.chorusBuffer(), 0)};
}

/// @returns the index of the first frame where the two differ, or `values.size()` if they are the same.
static size_t firstDifference(const std::vector<AUValue>& values, const std::vector<AUValue>& reference)
{
  auto [pos, _] = std::mismatch(values.begin(), values.end(), reference.begin());
  return size_t(pos - values.begin());
}

static constexpr size_t changeIndex = warmUpFrames + changeFrame;

@interface SliceControlsTests : XCTestCase
@end

@implementation SliceControlsTests

- (void)testPanChangeAppliesFromNextSlice {
  auto reference = render(nullptr);
  auto panned = render([](TestEngineHarness& harness) { harness.setParameter(Index::pan, -500); });
  XCTAssertEqual(firstDifference(panned.right, reference.right), changeIndex);
  for (auto index = changeIndex; index < totalFrames; ++index) {
    XCTAssertEqualWithAccuracy(panned.right[index], 0.0, 1.0e-6, @"frame %zu", index);
  }
  // Guard against a vacuous test: the note is sounding where the pan changes.
  XCTAssertGreaterThan(*std::max_element(panned.left.begin() + changeIndex, panned.left.end()), 0.1);
}

- (void)testChorusSendChangeAppliesFromNextSlice {
  auto reference = render(nullptr);
  auto sent = render([](TestEngineHarness& harness) { harness.setParameter(Index::chorusEffectSend, 500); });
  XCTAssertEqual(firstDifference(sent.chorus, reference.chorus), changeIndex);
  XCTAssertTrue(sent.left == reference.left);
  XCTAssertNotEqual(sent.chorus[changeIndex], 0.0f);
}

- (void)testAttenuationChangeAppliesFromNextSlice {
  auto reference = render(nullptr);
  auto quieter = render([](TestEngineHarness& harness) { harness.setParameter(Index::initialAttenuation, 60); });
  XCTAssertEqual(firstDifference(quieter.left, reference.left), changeIndex);
  // 6 dB of extra attenuation halves the level. Gain is applied before the (active) low-pass filter, whose history
  // smooths the step for a few samples, so compare once it has settled.
  for (auto index = totalFrames - 64; index < totalFrames; ++index) {
    XCTAssertEqualWithAccuracy(quieter.left[index], reference.left[index] * 0.501187, 1.0e-4, @"frame %zu", index);
  }
}

- (void)testPitchBendAppliesFromNextSlice {
  auto reference = render(nullptr);
  auto bent = render([](TestEngineHarness& harness) {
    harness.sendRaw(std::array<uint8_t, 3>{0xE0, 0x7F, 0x7F});
  });
  // The generator outputs the sample at its current position and then advances by the increment, so the new increment
  // shows in the second frame of the slice. (One held over for a whole slice would not show until frame 1024.)
  XCTAssertEqual(firstDifference(bent.left, reference.left), changeIndex + 1);
}

- (void)testVibratoDepthChangeAppliesFromNextSlice {
  // The minimal preset has no pitch modulation, so it uses the constant-increment path until the change. Turning on
  // vibrato must switch to the per-sample path in the next slice.
  auto reference = render(nullptr);
  auto vibrato = render([](TestEngineHarness& harness) { harness.setParameter(Index::vibratoLFOToPitch, 1200); });
  XCTAssertEqual(firstDifference(vibrato.left, reference.left), changeIndex + 1);
}

- (void)testFilterCutoffChangeAppliesWithinOneFilterUpdate {
  // The filter takes new inputs every `LowPassFilter::updateInterval` samples, so the change shows up at the next
  // update after the slice boundary, not necessarily in its first frame.
  auto reference = render(nullptr);
  auto filtered = render([](TestEngineHarness& harness) { harness.setParameter(Index::initialFilterCutoff, 6000); });
  auto first = firstDifference(filtered.left, reference.left);
  XCTAssertGreaterThanOrEqual(first, changeIndex);
  XCTAssertLessThan(first, changeIndex + Render::LowPassFilter::updateInterval);
}

- (void)testSliceSizeDoesNotChangeTheOutput {
  // Without events, rendering in 1-frame slices (controls captured every frame, as before §6 item 2) must give exactly
  // the same samples as rendering in 512-frame slices.
  auto whole = render(nullptr);
  auto harness{TestEngineHarness{48000.0}};
  harness.load(sinePath(), 0);
  auto mixer{harness.createMixer(double(totalFrames) / 48000.0)};
  harness.sendNoteOn(69, 127);
  for (AUAudioFrameCount frame = 0; frame < totalFrames; ++frame) harness.renderForCount(mixer, 1);
  const AUValue* left = harness.dryBuffer().floatChannelData[0];
  const AUValue* right = harness.dryBuffer().floatChannelData[1];
  XCTAssertTrue(whole.left == std::vector<AUValue>(left, left + totalFrames));
  XCTAssertTrue(whole.right == std::vector<AUValue>(right, right + totalFrames));
}

@end
