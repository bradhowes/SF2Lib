// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <iosfwd>

#include "SF2Lib/Types.hpp"

namespace SF2::DSP {

inline constexpr Float PI = Float(M_PI);
inline constexpr Float TwoPI = 2.0f * PI;
inline constexpr Float HalfPI = PI / 2.0f;
inline constexpr Float QuarterPI = PI/ 4.0f;

inline constexpr Float CentsPerOctave = 1200.0f;
inline constexpr Float CentibelsPerDecade = 200.0f;

/// Attenuated samples at or below this value will be inaudible.
inline constexpr Float NoiseFloor = 2.0E-7f;

/// Maximum attenuation defined by SF2 spec.
inline constexpr Float MaximumAttenuationCentiBels = 960.0f;

// 440 * pow(2.0, (N - 69) / 12)
inline constexpr Float LowestNoteFrequency = Float(8.17579891564370697665253828745335); // C-1

inline constexpr Float clamp(Float value, Float lowerBound, Float upperBound) {
  return std::min<Float>(std::max<Float>(value, lowerBound), upperBound);
}

/**
 Convert cents value into a power of 2. There are 1200 cents per power of 2.
 
 @param value the value to convert
 @returns power of 2 value
 */
inline Float centsToPower2(Float value) noexcept { return std::exp2(value / CentsPerOctave); }

/**
 Convert cents value into seconds, where There are 1200 cents per power of 2.

 @param value the number to convert
 */
inline Float centsToSeconds(Float value) noexcept { return centsToPower2(value); }

/**
 Convert cents to frequency, with 0 being 8.175798 Hz. Values are clamped to [-16000, 4500].
 
 @param value the value to convert
 @returns frequency in Hz
 */
inline Float lfoCentsToFrequency(Float value) noexcept {
  return LowestNoteFrequency * centsToPower2(clamp(value, -16000.0f, 4500.0f));
}

/**
 Convert centibels [0-1440] into an attenuation value from [1.0-0.0]. Zero indicates no attenuation (1.0), 60 is 0.5,
 and every 200 is a reduction by 10 (0.1, 0.001, etc.)

 @param centibels value to convert
 @returns gain value
 */
extern Float attenuationLookup(int centibels) noexcept;

/**
 Convert centiBels to resonance (Q) value for use in low-pass filter calculations. The input is clamped to the range
 given in SF2.01 spec #8.1.3. The factor being subtracted comes from FluidSynth code to conform to spec.

 @param centibels the value to convert
 */
inline double centibelsToResonance(double centibels) noexcept {
  return std::pow(10.0, (DSP::clamp(centibels, 0.0, 960.0) - 30.1) / 200.0);
}

/**
 Restrict lowpass filter cutoff value to be between 1500 and 13500, inclusive.
 
 @param value cutoff value
 @returns clamped cutoff value
 */
inline constexpr Float clampFilterCutoff(Float value) noexcept { return clamp(value, 1500.0f, 20000.0f); }

/**
 Convert integer from integer [0-1000] into [0.0-1.0]
 
 @param value percentage value expressed as tenths
 @returns normalized value between 0 and 1.
 */
inline constexpr Float tenthPercentageToNormalized(Float value) noexcept { return clamp(value / 1000.0f, 0.0f, 1.0f); }

/**
 Translate value in range [0, +1] into one in range [-1, +1]
 
 @param modulator the value to translate
 @returns value in range [-1, +1]
 */
inline constexpr Float unipolarToBipolar(Float modulator) noexcept { return 2.0f * modulator - 1.0f; }

/**
 Translate value in range [-1, +1] into one in range [0, +1]
 
 @param modulator the value to translate
 @returns value in range [0, +1]
 */
inline constexpr Float bipolarToUnipolar(Float modulator) noexcept { return 0.5f * modulator + 0.5f; }

/**
 Perform linear translation from a value in range [0.0, 1.0] into one in [minValue, maxValue].
 
 @param modulator the value to translate
 @param minValue the lowest value to return when modulator is 0
 @param maxValue the highest value to return when modulator is +1
 @returns value in range [minValue, maxValue]
 */
inline constexpr Float unipolarModulate(Float modulator, Float minValue, Float maxValue) noexcept {
  return clamp(modulator, 0.0f, 1.0f) * (maxValue - minValue) + minValue;
}

/**
 Perform linear translation from a value in range [-1.0, 1.0] into one in [minValue, maxValue]
 
 @param modulator the value to translate
 @param minValue the lowest value to return when modulator is -1
 @param maxValue the highest value to return when modulator is +1
 @returns value in range [minValue, maxValue]
 */
inline constexpr Float bipolarModulate(Float modulator, Float minValue, Float maxValue) noexcept {
  auto mid = (maxValue - minValue) * 0.5f;
  return clamp(modulator, -1.0f, 1.0f) * mid + mid + minValue;
}

/**
 Estimate sin() value from a radian angle between -PI and PI.
 Derived from code in "Designing Audio Effect Plugins in C++" by Will C. Pirkle (2019)
 As can be seen in the unit test `testParabolicSineAccuracy`, the worst-case deviation from
 std::sin is ~0.0011.
 
 @param angle value between -PI and PI
 @returns approximate sin value
 */
constexpr Float parabolicSine(Float angle) noexcept {
  constexpr auto B = 4.0f / PI;
  constexpr auto C = -4.0f / (PI * PI);
  constexpr auto P = 0.225f;
  const auto y = B * angle + C * angle * (angle >= 0.0f ? angle : -angle);
  return P * y * ((y >= 0.0f ? y : -y) - 1.0f) + y;
}

/**
 Calculate the amount of left and right signal gain in [0.0-1.0] for the given `pan` value which is in range
 [-500, +500]. A `pan` of -500 is only left, and +500 is only right. A `pan` of 0 should result in ~0.7078 for both,
 but moving left/right will increase one channel to 1.0 while the other falls off to 0.0.
 
 @param pan the value to convert
 @param left reference to storage for the left gain
 @param right reference to storage for the right gain
 */
extern void panLookup(Float pan, Float& left, Float& right) noexcept;

extern double centsPartialLookup(int partial) noexcept;

/**
 Quickly convert cent value into a frequency using a table lookup. These calculations are taken from the Fluid Synth
 fluid_conv.c file, in particular the fluid_ct2hz_real function. Uses CentPartialLookup above to convert values from
 0 - 1199 into the proper multiplier.
 */
inline double centsToFrequency(Float value) noexcept {
  if (value < 0.0f) return 1.0f;

  // This seems to be the fastest way to do the following. Curiously, the operation `cents % 1200` is faster than doing
  // `cents - whole * 1200` in optimized build.
  auto cents = int(value + 300);
  auto whole = cents / 1200;
  auto partial = cents % 1200;
  return (1u << whole) * centsPartialLookup(partial);
}

namespace Interpolation {

/**
 Interpolate a value from two values.

 @param partial indication of affinity for one of the two values. Values [0-0.5) favor x0, while values (0.5-1.0)
 favor x1. A value of 0.5 equally favors both.
 @param x0 first value to use
 @param x1 second value to use
 */
inline constexpr Float linear(Float partial, Float x0, Float x1) noexcept { return partial * (x1 - x0) + x0; }

/**
 Types and configuration for the cubic 4th order interpolator.
 */
struct Cubic4thOrder {
  static constexpr size_t TableSize = 1024;
  using WeightsEntry = std::array<double, 4>;

  static const WeightsEntry& weights(size_t index) noexcept;
};

/**
 Interpolate a value from four values.

 @param partial location between the second value and the third. By definition it should always be < 1.0
 @param x0 first value to use
 @param x1 second value to use
 @param x2 third value to use
 @param x3 fourth value to use
 */
inline static Float cubic4thOrder(Float partial, Float x0, Float x1, Float x2, Float x3) noexcept {
  auto index = size_t(partial * Cubic4thOrder::TableSize);
  assert(index < Cubic4thOrder::TableSize);
  const auto& w{Cubic4thOrder::weights(index)};
  return x0 * w[0] + x1 * w[1] + x2 * w[2] + x3 * w[3];
}

} // Interpolation namespace

/**
 Convert centiBels to attenuation, where 60 corresponds to a drop of 6dB or 0.5 reduction of audio samples. Note that
 for raw generator values in an SF2 file, better to use the attenuationLookup(int) method above. However, this
 method uses it as well, though with an additional step of performing linear interpolation to arrive at the
 final value.

 @param centibels the value to convert
 @returns attenuation amount
 */
inline Float centibelsToAttenuation(Float centibels) noexcept {
  centibels = DSP::clamp(centibels, 0.0, 1440.0);
  auto index1 = int(centibels);
  auto partial = centibels - index1;
  if (partial < std::numeric_limits<Float>::min()) return attenuationLookup(index1);
  auto index2 = std::min<int>(index1 + 1, 1440);
  return Interpolation::linear(partial, attenuationLookup(index1), attenuationLookup(index2));
}

} // SF2::DSP namespaces
