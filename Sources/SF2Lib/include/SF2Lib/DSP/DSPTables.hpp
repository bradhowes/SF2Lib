//// Copyright © 2022 Brad Howes. All rights reserved.
//
//#pragma once
//
///**
// Namespace for compile-time generated tables. Each table is encapsulated in a `struct` that has three components:
// 
// - a `TableSize` definition that states how many entries are in the table (all tables hold `Float` values).
// - a `lookup_` class attribute that declares the lookup table
// - a `value` class method that returns the `Float` value to store at a given table index
// 
// All structs also include a class method that performs a lookup for a given value. However, this is not used by the
// table generating infrastructure.
// */
//namespace SF2::DSP::Tables {
//
//struct Generator;
//
///**
// Interpolation using a cubic 4th-order polynomial. The coefficients of the polynomial are stored in a lookup table that
// is generated at compile time.
// */
//struct Cubic4thOrder {
//  
//  /// Number of weights (x4) to generate.
//  inline constexpr static size_t TableSize = 1024;
//  
//  using WeightsArray = std::array<std::array<double, 4>, TableSize>;
//  
//  /**
//   Interpolate a value from four values.
//   
//   @param partial location between the second value and the third. By definition it should always be < 1.0
//   @param x0 first value to use
//   @param x1 second value to use
//   @param x2 third value to use
//   @param x3 fourth value to use
//   */
//  inline static double interpolate(Float partial, Float x0, Float x1, Float x2, Float x3) noexcept {
//    auto index = size_t(partial * TableSize);
//    assert(index < TableSize); // should always be true based on definition of `partial`
//    const auto& w{weights_[index]};
//    return x0 * w[0] + x1 * w[1] + x2 * w[2] + x3 * w[3];
//  }
//  
//private:
//  
//  /**
//   Array of weights used during interpolation. Initialized at startup.
//   */
//  static const WeightsArray weights_;
//  Cubic4thOrder() = delete;
//  friend struct Generator;
//};
//
//} // SF2::DSP::Tables namespaces
