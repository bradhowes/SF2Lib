// Copyright © 2026 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

using namespace SF2;
using Index = SF2::Entity::Generator::Index;

// SF2.01 8.1.2 #34 attackVolEnv: "the attack is 'convex'; the curve is nominally such that when applied to the decibel
// volume parameter, the result is linear in amplitude." The voice now applies the attack as a linear amplitude
// fraction instead of shaping it with `log10` and converting back through whole centibels.

static constexpr AUAudioFrameCount renderFrames = 4'800;

/**
 Play one note with no volume envelope delay and the low-pass filter bypassed (cutoff above
 `LowPassFilter::bypassFrequency`, no resonance), so the output is the interpolated sample times the gain.

 The values are put in the instrument zone. (`LiveGeneratorRangeTests` checks that the same values set live give
 the same result.)

 @param attackTimecents the attackVolEnv value to use
 @returns the left channel
 */
static std::vector<AUValue> render(int16_t attackTimecents)
{
  constexpr uint16_t genInitialFilterCutoff = 8;
  constexpr uint16_t genDelayVolEnv = 33;
  constexpr uint16_t genAttackVolEnv = 34;
  auto builder = SF2Builder::minimal();
  builder.igen = {{genInitialFilterCutoff, 13'600}, {genDelayVolEnv, uint16_t(int16_t(-32'768))},
    {genAttackVolEnv, uint16_t(attackTimecents)}, {SF2Builder::genSampleModes, 1}, {SF2Builder::genSampleID, 0},
    {0, 0}};
  builder.ibag = {{0, 0}, {5, 0}};
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibVolumeAttack.sf2";
  builder.writeTo(path);

  auto harness{TestEngineHarness{48000.0}};
  harness.load(path, 0);
  auto mixer{harness.createMixer(double(renderFrames) / 48000.0)};
  harness.sendNoteOn(69, 127);
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + renderFrames);
}

@interface VolumeAttackTests : XCTestCase
@end

@implementation VolumeAttackTests

- (void)testAttackIsLinearInAmplitude {
  // A 2 s attack (1200 timecents) against an instant one (-32768 gives a 1-sample attack). Each output frame of the slow
  // attack must be the instant frame scaled by the attack progress, about (k + 1) / 96000. With the old per-sample
  // `log10` and rounding to whole centibels, the ratio was off by up to 0.58%.
  auto slow = render(1'200);
  auto instant = render(-32'768);
  // The envelope accumulates the progress in `Float`, one increment of 1/96000 per sample, so do the same here.
  Float increment = 1_F / Float(2 * 48'000);
  Float progress = 0_F;
  double largest = 0.0;
  for (size_t index = 0; index < renderFrames; ++index) {
    progress = std::min<Float>(progress + increment, 1_F);
    double expected = double(progress) * double(instant[index]);
    XCTAssertEqualWithAccuracy(double(slow[index]), expected, 1.0e-6 * std::abs(expected) + 1.0e-12, @"frame %zu",
                               index);
    largest = std::max(largest, std::abs(double(instant[index])));
  }
  // Guard against a vacuous test: the reference is sounding.
  XCTAssertGreaterThan(largest, 0.1);
}

@end
