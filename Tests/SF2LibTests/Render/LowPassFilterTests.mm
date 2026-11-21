// Copyright © 2026 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>
#include <cmath>
#include <vector>

#include "SF2Util/DSP.hpp"
#include "SF2Lib/Render/LowPassFilter.hpp"

using namespace SF2;
using namespace SF2::Render;

static constexpr Float sampleRate = 48'000.0;

/**
 Drive a filter with a unit sine at `hz` for one second and return the steady-state gain: the RMS ratio of output to
 input over the last half second. All test frequencies complete a whole number of cycles in that half second.
 */
static double gainAt(double hz, Float cutoffCents, Float resonanceCB)
{
  LowPassFilter filter{sampleRate};
  filter.reset();
  double inSum = 0.0;
  double outSum = 0.0;
  auto count = size_t(sampleRate);
  for (size_t index = 0; index < count; ++index) {
    if (filter.needsUpdate()) filter.update(cutoffCents, resonanceCB);
    auto x = std::sin(2.0 * M_PI * hz * double(index) / sampleRate);
    auto y = filter.transform(x);
    if (index >= count / 2) {
      inSum += x * x;
      outSum += y * y;
    }
  }
  return std::sqrt(outSum / inSum);
}

/// @returns absolute cents for a frequency in Hz (inverse of `DSP::centsToFrequency`).
static Float hzToCents(double hz) { return Float(1200.0 * std::log2(hz / 8.17579891564)); }

@interface LowPassFilterTests : XCTestCase
@end

@implementation LowPassFilterTests

- (void)testNonResonantResponse {
  // Q = 0 cB is a Butterworth response: unity at DC, -3 dB at the cutoff and -12 dB/octave above it.
  auto cutoff = hzToCents(1000.0);
  XCTAssertEqualWithAccuracy(gainAt(20.0, cutoff, 0), 1.0, 0.001);
  XCTAssertEqualWithAccuracy(gainAt(1000.0, cutoff, 0), M_SQRT1_2, 0.01);
  XCTAssertLessThan(gainAt(8000.0, cutoff, 0), 0.02);
}

- (void)testCutoffTracksGeneratorValue {
  // Gain at the cutoff is -3 dB wherever the cutoff is placed.
  for (double hz : {100.0, 440.0, 2000.0, 8000.0}) {
    XCTAssertEqualWithAccuracy(gainAt(hz, hzToCents(hz), 0), M_SQRT1_2, 0.01, @"cutoff %f", hz);
  }
}

- (void)testResonanceReducesDCGainByHalfTheResonance {
  // SF2.01 8.1.2 #9: for Q = 100 cB the DC gain is 5 dB below unity.
  auto cutoff = hzToCents(2000.0);
  auto expected = std::pow(10.0, -5.0 / 20.0);
  XCTAssertEqualWithAccuracy(gainAt(20.0, cutoff, 100), expected, expected * 0.01);

  // And for Q = 400 cB it is 20 dB below unity. (Much higher Q values ring for longer than the measurement window.)
  expected = std::pow(10.0, -20.0 / 20.0);
  XCTAssertEqualWithAccuracy(gainAt(20.0, cutoff, 400), expected, expected * 0.01);
}

- (void)testResonantPeakIsAboveDCGain {
  // The gain at the cutoff relative to the DC gain is the linear Q, which SF2Lib (like FluidSynth) derives from the
  // centibel value with a 3.01 dB offset so that 0 cB means "no resonance" (Q = 1/sqrt(2)).
  auto cutoff = hzToCents(2000.0);
  for (Float resonance : {100_F, 200_F, 400_F}) {
    auto relative = gainAt(2000.0, cutoff, resonance) / gainAt(20.0, cutoff, resonance);
    auto expected = SF2::DSP::centibelsToResonance(resonance);
    XCTAssertEqualWithAccuracy(relative, expected, expected * 0.02, @"resonance %f", resonance);
    XCTAssertGreaterThan(relative, 1.0);
  }
}

- (void)testBypassAboveTwentyKilohertzWithoutResonance {
  // SF2.01 8.1.2 #8: cutoff above 20 kHz with zero Q does not affect the signal.
  LowPassFilter filter{sampleRate};
  filter.reset();
  XCTAssertTrue(filter.needsUpdate());
  filter.update(13'600, 0);
  XCTAssertTrue(filter.isBypassed());
  for (size_t index = 0; index < 1000; ++index) {
    filter.needsUpdate();
    auto x = std::sin(2.0 * M_PI * 15'000.0 * double(index) / sampleRate);
    XCTAssertEqual(filter.transform(x), x);
  }

  // Any resonance, or a cutoff at or below 13500 cents (~19.9 kHz), keeps the filter active.
  filter.reset();
  filter.needsUpdate();
  filter.update(13'600, 10);
  XCTAssertFalse(filter.isBypassed());
  filter.reset();
  filter.needsUpdate();
  filter.update(13'500, 0);
  XCTAssertFalse(filter.isBypassed());
}

- (void)testUpdateInterval {
  LowPassFilter filter{sampleRate};
  filter.reset();
  XCTAssertTrue(filter.needsUpdate());
  for (size_t index = 1; index < LowPassFilter::updateInterval; ++index) {
    XCTAssertFalse(filter.needsUpdate());
  }
  XCTAssertTrue(filter.needsUpdate());

  // A reset makes the next sample update straight away.
  XCTAssertFalse(filter.needsUpdate());
  filter.reset();
  XCTAssertTrue(filter.needsUpdate());
}

- (void)testSweptCutoffIsStableAndContinuous {
  // Sweep the cutoff across its full range with a resonant setting, as an LFO or envelope would. The output must stay
  // finite and bounded, and never jump by more than a small amount between samples for a low-frequency input.
  LowPassFilter filter{sampleRate};
  filter.reset();
  Float previous = 0_F;
  Float maxStep = 0_F;
  auto count = size_t(sampleRate);
  for (size_t index = 0; index < count; ++index) {
    auto phase = double(index) / double(count);
    if (filter.needsUpdate()) filter.update(Float(1'500.0 + 12'000.0 * (0.5 - 0.5 * std::cos(8.0 * M_PI * phase))), 200);
    auto y = filter.transform(std::sin(2.0 * M_PI * 110.0 * double(index) / sampleRate));
    XCTAssertTrue(std::isfinite(y));
    XCTAssertLessThan(std::abs(y), 4.0);
    if (index > 0) maxStep = std::max(maxStep, Float(std::abs(y - previous)));
    previous = y;
  }
  XCTAssertLessThan(maxStep, 0.1);
}

@end
