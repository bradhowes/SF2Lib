// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

/**
 Namespace for compile-time generated tables. Each table is encapsulated in a `struct` that has three components:
 
 - a `TableSize` definition that states how many entries are in the table (all tables hold `Float` values).
 - a `lookup_` class attribute that declares the lookup table
 - a `value` class method that returns the `Float` value to store at a given table index
 
 All structs also include a class method that performs a lookup for a given value. However, this is not used by the
 table generating infrastructure.
 */
namespace SF2::DSP::Tables {

struct Generator;

/**
 Convert cents [0-1200) into frequency multiplier. This is used by the centsToFrequency() function to perform a fast
 conversion between cents and frequency.
 */
struct CentsPartialLookup {
  inline constexpr static int MaxCentsValue = 1200;
  inline constexpr static size_t TableSize = MaxCentsValue;

  /**
   Convert a value between 0 and 1200 into a frequency multiplier. See DSP::centsToFrequency for details on how it is
   used.

   @param partial a value between 0 and MaxCentsValue - 1
   @returns frequency multiplier
   */
  static double convert(int partial) noexcept { return lookup_[size_t(std::clamp(partial, 0, MaxCentsValue - 1))]; }
  
private:
  static double value(size_t index) { return 6.875 * std::exp2(double(index) / 1200.0); }
  static const std::array<double, TableSize> lookup_;
  CentsPartialLookup() = delete;
  friend struct Generator;
};

/**
 Convert centibels into attenuation via table lookup.
 */
struct AttenuationLookup {
  inline constexpr static size_t TableSize = 1441;
  
  /**
   Convert from integer (generator) value to attenuation.
   
   @param centibels value to convert
   */
  static double convert(int centibels) noexcept {
    return lookup_[size_t(std::clamp<int>(centibels, 0, TableSize - 1))];
  }
  
  /**
   Convert from floating-point value to attenuation. Rounds to nearest integer to obtain index.
   
   @param centibels value to convert
   */
  static double convert(Float centibels) noexcept { return convert(int(std::round(centibels))); }
  
private:
  static const std::array<double, TableSize> lookup_;
  
  static double value(size_t index) { return centibelsToAttenuation(index); }
  
  AttenuationLookup() = delete;
  friend struct Generator;
};

/**
 Convert centibels into gain value (same as 1.0 / attenuation)
 */
struct GainLookup {
  inline constexpr static size_t TableSize = 1441;
  
  /**
   Convert from integer (generator) value to gain
   
   @param centibels value to convert
   */
  static double convert(int centibels) noexcept {
    return lookup_[size_t(std::clamp<int>(centibels, 0, TableSize - 1))];
  }
  
  /**
   Convert from floating-point value to gain. Rounds to nearest integer to obtain index.
   
   @param centibels value to convert
   */
  static double convert(Float centibels) noexcept { return convert(int(std::round(centibels))); }
  
private:
  static double value(size_t index) { return 1.0 / centibelsToAttenuation(index); }
  static const std::array<double, TableSize> lookup_;
  GainLookup() = delete;
  friend struct Generator;
};

/**
 Interpolation using a cubic 4th-order polynomial. The coefficients of the polynomial are stored in a lookup table that
 is generated at compile time.
 */
struct Cubic4thOrder {
  
  /// Number of weights (x4) to generate.
  inline constexpr static size_t TableSize = 1024;
  
  using WeightsArray = std::array<std::array<double, 4>, TableSize>;
  
  /**
   Interpolate a value from four values.
   
   @param partial location between the second value and the third. By definition it should always be < 1.0
   @param x0 first value to use
   @param x1 second value to use
   @param x2 third value to use
   @param x3 fourth value to use
   */
  inline static double interpolate(Float partial, Float x0, Float x1, Float x2, Float x3) noexcept {
    auto index = size_t(partial * TableSize);
    assert(index < TableSize); // should always be true based on definition of `partial`
    const auto& w{weights_[index]};
    return x0 * w[0] + x1 * w[1] + x2 * w[2] + x3 * w[3];
  }
  
private:
  
  /**
   Array of weights used during interpolation. Initialized at startup.
   */
  static const WeightsArray weights_;
  Cubic4thOrder() = delete;
  friend struct Generator;
};

} // SF2::DSP::Tables namespaces
