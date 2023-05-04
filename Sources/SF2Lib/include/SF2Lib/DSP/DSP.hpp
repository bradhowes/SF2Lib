// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <iosfwd>

#include "DSPHeaders/DSP.hpp" // AUv3Support include
#include "SF2Lib/Types.hpp"

/// Functions and constants for general-purpose signal processing specific to SF2 realm. More general-purpose routines
/// are in the DSPHeaders::DSP namespace of AUv3Support package.
namespace SF2::DSP {

/// Number of cents in an octave
inline constexpr Float CentsPerOctave = 1200.0f;

/// Attenuated samples at or below this value will be inaudible (I think).
inline constexpr Float NoiseFloor = 2.0E-7f;

/// Maximum attenuation defined by SF2 spec.
inline constexpr Float MaximumAttenuationCentiBels = 960.0f;

/// Lowest note frequency that we can generate. This corresponds to C-1 in MIDI nomenclature
/// (440 * pow(2.0, (N - 69) / 12))
inline constexpr Float LowestNoteFrequency = Float(8.17579891564370697665253828745335);

/////
//inline constexpr Float clamp(Float value, Float lowerBound, Float upperBound) {
//  return std::clamp(value, lowerBound, upperBound);
//}

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
  return LowestNoteFrequency * centsToPower2(std::clamp(value, -16000.0, 4500.0));
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
inline Float centibelsToResonance(Float centibels) noexcept {
  return std::pow(10.0, (std::clamp(centibels, 0.0, 960.0) - 30.1) / 200.0);
}

/**
 Restrict lowpass filter cutoff value to be between 1500 and 13500, inclusive.
 
 @param value cutoff value
 @returns clamped cutoff value
 */
inline constexpr Float clampFilterCutoff(Float value) noexcept { return std::clamp(value, 1500.0, 20000.0); }

/**
 Convert integer from integer [0-1000] into [0.0-1.0]
 
 @param value percentage value expressed as tenths
 @returns normalized value between 0 and 1.
 */
inline constexpr Float tenthPercentageToNormalized(Float value) noexcept {
  return std::clamp(value / 1000.0, 0.0, 1.0);
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

extern Float centsPartialLookup(int partial) noexcept;

/**
 Quickly convert cent value into a frequency using a table lookup. These calculations are taken from the Fluid Synth
 fluid_conv.c file, in particular the fluid_ct2hz_real function. Uses CentPartialLookup above to convert values from
 0 - 1199 into the proper multiplier.
 */
inline Float centsToFrequency(Float value) noexcept {
  if (value < 0.0f) [[unlikely]] return 1.0f;

  // This seems to be the fastest way to do the following. Curiously, the operation `cents % 1200` is faster than doing
  // `cents - whole * 1200` in optimized build.
  auto cents = int(value + 300);
  auto whole = cents / 1200;
  auto partial = cents % 1200;
  return (1u << whole) * centsPartialLookup(partial);
}

/**
 Convert centiBels to attenuation, where 60 corresponds to a drop of 6dB or 0.5 reduction of audio samples. Note that
 for raw generator values in an SF2 file, better to use the attenuationLookup(int) method above. However, this
 method uses it as well, though with an additional step of performing linear interpolation to arrive at the
 final value.

 @param centibels the value to convert
 @returns attenuation amount
 */
inline Float centibelsToAttenuation(Float centibels) noexcept {
  centibels = std::clamp(centibels, 0.0, 1440.0);
  auto index1 = int(centibels);
  auto partial = centibels - index1;
  if (partial < std::numeric_limits<Float>::min()) return attenuationLookup(index1);
  auto index2 = std::min<int>(index1 + 1, 1440);
  return DSPHeaders::DSP::Interpolation::linear(partial, attenuationLookup(index1), attenuationLookup(index2));
}

} // SF2::DSP namespaces
