// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <iosfwd>

#include "DSPHeaders/ConstMath.hpp"
#include "DSPHeaders/DSP.hpp"
#include "SF2Lib/Types.hpp"

/// Functions and constants for general-purpose signal processing specific to SF2 realm. More general-purpose routines
/// are in the DSPHeaders::DSP namespace of AUv3Support package.
namespace SF2::DSP {

/// Maximum absolute cents that will be used for frequencies. This corresponds to 20 kHz.
inline constexpr int MaximumAbsoluteCents = 13'508;

/// Number of cents in an octave
inline constexpr int CentsPerOctave = 1'200;

/// Attenuated samples at or below this value will be inaudible (I think).
inline constexpr Float NoiseFloor = 2.0E-7f;

/// Maximum attenuation defined by SF2 spec.
inline constexpr Float MaximumAttenuationCentiBels = 1'440.0f;

/// Lowest note frequency that we can generate. This corresponds to C-1 in MIDI nomenclature
/// (440 * pow(2.0, (N - 69) / 12))
inline constexpr Float LowestNoteFrequency = Float(8.17579891564370697665253828745335);

inline constexpr Float clamp(Float value, Float lowerBounds, Float upperBounds) noexcept {
  return std::clamp(value, lowerBounds, upperBounds);
}

/**
 Lookup table for converting centibels to attenuation.
 */
struct AttenuationLookup {
  static constexpr Float query(int centibels) noexcept {
    return lookup_[static_cast<size_t>(std::clamp<int>(centibels, 0, int(TableSize - 1)))];
  }

private:
  static constexpr size_t TableSize = size_t(MaximumAttenuationCentiBels + 1);
  static constexpr Float generator(size_t index) {
    // Equivalent to pow(10.0, Float(index) / -200.0)
    return DSPHeaders::ConstMath::exp(Float(index) / Float(-200.0) * DSPHeaders::ConstMath::Constants<Float>::ln10);
  }

  static inline const auto lookup_ = DSPHeaders::ConstMath::make_array<Float, TableSize>(generator);
};

/**
 Convert centibels [0-1440] into an attenuation value from [1.0-0.0].

 - Zero indicates no attenuation (1.0)
 -  20 centibels (-2 dB) gives 0.1 attenuation (10% reduction of original signal)
 -  60 centibels (-6 dB) gives 0.5 attenuation (50% reduction of original signal)
 - 120 centibels (-12 dB) gives 0.25 attenuation

 and every 200 is a reduction by a power of 10 (200 = 0.1, 400 = 0.001, etc.)

 NOTE: attenuation greater than 96 dB is in the noise floor for 16-bit samples.

 @param value value in centibels to convert
 @returns attenuation value
 */
inline Float centibelsToAttenuation(Float value) noexcept {
  extern Float attenuationLookup(int centibels) noexcept;
  if (value >= MaximumAttenuationCentiBels) return 0.0f;
  if (value <= 0.0f) return 1.0f;
  return AttenuationLookup::query(int(nearbyint(value)));
}

/**
 Convert a floating-point centibels value into an attenuation.

 @param value value in centibels to convert
 @returns attenuation value
 */
inline Float centibelsToAttenuationInterpolated(Float value) noexcept {
  auto index = int(value);
  auto partial = value - index;
  return Float(DSPHeaders::DSP::Interpolation::linear(partial,
                                                      centibelsToAttenuation(index),
                                                      centibelsToAttenuation(index + 1)));
}

/**
 Lookup table definition for cents to frequency values in range [0 - 1200).
 */
struct CentsPartialLookup {

  /// @return the value frequency for the given cents.
  static constexpr Float query(int cents) noexcept {
    return lookup_[static_cast<size_t>(std::clamp<int>(cents, 0, int(TableSize - 1)))];
  }

private:
  static constexpr size_t TableSize = size_t(CentsPerOctave);
  static constexpr Float generator(size_t index) {
    // 6.875 x 2^(index / 1200) ==> 6.875 x e^(index / 1200 * ln(2))
    return 6.875f * DSPHeaders::ConstMath::exp(index / Float(CentsPerOctave) * DSPHeaders::ConstMath::Constants<Float>::ln2);
  }

  static inline const auto lookup_ = DSPHeaders::ConstMath::make_array<Float, TableSize>(generator);
};

/**
 Convert a cents value in range [0-1200) into frequency.

 @param value value to convert
 @returns converted value
 */
constexpr Float centsPartialLookup(int value) noexcept { return CentsPartialLookup::query(value); }

/**
 Lookup table definition for power of 2 values. The range covers [-12,000, +12,000] cents, which is overly broad for
 well-designed SF2 files.
 */
struct Power2Lookup {

  /// @return the value 2 ^ cents
  static constexpr Float query(int cents) noexcept {
    return lookup_[static_cast<size_t>(std::clamp<int>(cents + Offset, 0, int(TableSize - 1)))];
  }

private:
  static constexpr int Range = CentsPerOctave * 10 * 2 + 1;
  static constexpr int Offset = Range / 2;
  static constexpr size_t TableSize = Range;
  static constexpr Float generator(size_t index) {
    return DSPHeaders::ConstMath::pow(Float(2.0), Float(int(index) - Offset) / Float(CentsPerOctave));
  }

  static inline const auto lookup_ = DSPHeaders::ConstMath::make_array<Float, TableSize>(generator);
};

constexpr Float power2Lookup(int cents) noexcept { return Power2Lookup::query(cents); }

/**
 Lookup table for SF2 pan values, where -500 means only left-channel, and +500 means only right channel. Other values
 give attenuation values for the left and right channels between 0.0 and 1.0. These values come from the sine function
 for a pleasing audio experience when panning.

 NOTE: FluidSynth has a table size of 1002 for some reason. Thus its values are slightly off from what this table
 contains. I don't see a reason for the one extra element.
 */
struct PanLookup {
  static inline void query(Float pan, Float& left, Float& right) noexcept {
    int index = std::clamp(static_cast<int>(std::round(pan)), -500, 500);
    left = lookup_[static_cast<size_t>(-index + 500)];
    right = lookup_[static_cast<size_t>(index + 500)];
  }

private:
  static constexpr size_t TableSize = 500 + 500 + 1;
  static constexpr Float Scaling = DSPHeaders::ConstMath::Constants<Float>::HalfPI / (TableSize - 1);
  static constexpr Float generator(size_t index) { return DSPHeaders::ConstMath::sin(index * Scaling); }

  static inline const auto lookup_ = DSPHeaders::ConstMath::make_array<Float, TableSize>(generator);
};

/**
 Calculate the amount of left and right signal gain in [0.0-1.0] for the given `pan` value which is in range
 [-500, +500]. A `pan` of -500 is only left, and +500 is only right. A `pan` of 0 should result in ~0.7078 for both,
 but moving left/right will increase one channel to 1.0 while the other falls off to 0.0.

 @param value the value to convert
 @param left reference to storage for the left gain
 @param right reference to storage for the right gain
 */
inline void panLookup(Float value, Float& left, Float& right) noexcept { PanLookup::query(value, left, right); }

/**
 Convert cents value into a power of 2. There are 1200 cents per power of 2.
 
 @param value the value to convert
 @returns power of 2 value
 */
inline Float centsToPower2(Float value) noexcept { return std::exp2(value / CentsPerOctave); }

/**
 Convert cents value into seconds, where there are 1200 cents per power of 2.

 @param value the number to convert in time cents
 @returns duration in seconds
 */
inline Float centsToSeconds(Float value) noexcept { return centsToPower2(value); }

/**
 Convert cents to frequency, with 0 being 8.175798 Hz. Values are clamped to [-16000, 4500].
 
 @param value the value to convert
 @returns frequency in Hz
 */
inline Float lfoCentsToFrequency(Float value) noexcept {
  return LowestNoteFrequency * centsToPower2(clamp(value, -16'000.0f, 4'500.0f));
}

/**
 Convert centiBels to resonance (Q) value for use in low-pass filter calculations. The input is clamped to the range
 given in SF2.01 spec #8.1.3. The factor being subtracted comes from FluidSynth code to conform to spec.

 @param value the value to convert
 */
inline Float centibelsToResonance(Float value) noexcept {
  return Float(std::pow(10.0, (clamp(value, 0.0f, 960.0f) - Float(30.1)) / Float(200.0)));
}

/**
 Restrict lowpass filter cutoff value to be between 1500 and 13500, inclusive.

 @param value cutoff value
 @returns clamped cutoff value
 */
inline constexpr Float clampFilterCutoff(Float value) noexcept { return clamp(value, 1'500.0f, 20'000.0f); }

/**
 Convert integer from integer [0-1000] into [0.0-1.0]
 
 @param value percentage value expressed as tenths
 @returns normalized value between 0 and 1.
 */
inline constexpr Float tenthPercentageToNormalized(Float value) noexcept {
  return clamp(value / Float(1'000.0), 0.0f, 1.0f);
}

/**
 Quickly convert absolute cents value into a frequency. Valid inputs are 0 - 13,508 which translates to
 6.875 Hz - 28 kHz (20,004.35). Higher values could be supported but for no real reason in SF2Lib.

 @param value the value in cents to convert
 @returns frequency of the given cents value
 */
inline Float centsToFrequency(Float value) noexcept {
  if (value < 0.0f) return 1.0f;
  if (value > MaximumAbsoluteCents) value = MaximumAbsoluteCents;
  auto cents = int(value + 300);
  auto whole = cents / 1'200;
  auto partial = cents % 1'200;
  // Limit of 13508 means that `whole` will not be larger than 11, so this should be safe on all machines that we will
  // run on.
  return (1u << whole) * centsPartialLookup(partial);
}

} // SF2::DSP namespaces
