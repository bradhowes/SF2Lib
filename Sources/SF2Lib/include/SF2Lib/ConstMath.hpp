// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace SF2::ConstMath {

// Based on work from https://github.com/lakshayg/compile_time

template <typename T>
struct constants {
  static constexpr T e = T(2.71828182845904523536);
  static constexpr T log2e = T(1.44269504088896340736);
  static constexpr T log10e = T(0.434294481903251827651);
  static constexpr T ln2 = T(0.693147180559945309417);
  static constexpr T ln10 = T(2.30258509299404568402);
  static constexpr T PI = T(3.14159265358979323846);
  static constexpr T TwoPI = 2 * PI;
  static constexpr T HalfPI = PI / 2.0;
  static constexpr T QuarterPI = PI / 4.0;
};

template <typename T, std::size_t N, typename Generator>
constexpr std::array<T, N> make_array(Generator fn) noexcept {
  std::array<T, N> table = {};
  for (std::size_t i = 0; i != N; ++i) table[i] = fn(i);
  return table;
}

template <typename T>
constexpr T PI{M_PI};

template <typename T>
constexpr T squared(T x) noexcept { return x * x; }

template <typename T>
constexpr T normalizeRadians(T theta) noexcept {
  T PI = constants<T>::PI;
  return (theta <= -PI) ? (theta + PI * 2) : (theta > PI) ? (theta - PI * 2) : theta;
}

template <typename T>
constexpr T sin_cfrac(T x2, int k = 2, int n = 40) noexcept {
  return (n == 0) ? k * (k + 1) - x2 : k * (k + 1) - x2 + (k * (k + 1) * x2) / sin_cfrac(x2, k + 2, n - 1);
}

template <typename T>
constexpr T tan_cfrac(T x2, int k = 1, int n = 40) noexcept {
  return (n == 0) ? k : k - x2 / tan_cfrac(x2, k + 2, n - 1);
}

template <typename T>
constexpr T fast_atan_unit(T x) noexcept {  // -1 <= x <= 1
  return constants<T>::QuarterPI * x - x * (abs(x) - 1) * (0.2447 + 0.0663 * abs(x));
}

template <typename T>
constexpr T sin(T theta) noexcept {
  T normTheta = normalizeRadians(theta);
  T normTheta2 = squared(normTheta);
  return normTheta / (1 + normTheta2) / sin_cfrac(normTheta2);
}

template <typename T>
constexpr T cos(T theta) { return sin(constants<T>::HalfPI - theta); }

template <typename T, typename Integer>
constexpr Integer floor(T x) {
  static_assert(std::is_floating_point_v<T>, "floor accepts only floating point inputs");
  return static_cast<Integer>(x) - (static_cast<Integer>(x) > x);
}

template <typename T, typename Integer>
constexpr Integer ceil(T x) {
  static_assert(std::is_floating_point_v<T>, "floor accepts only floating point inputs");
  return static_cast<Integer>(x) + (static_cast<Integer>(x) < x);
}

template <typename T>
constexpr T exp_frac_helper(T x2, int iter = 5, int k = 6) {
  return (iter > 0) ? k + x2 / exp_frac_helper(x2, iter - 1, k + 4) : k + x2 / (k + 4);
}

template <typename T>
constexpr T exp_frac(T x) {
  return (x != 0) ? 1 + 2 * x / (2 - x + (x * x) / exp_frac_helper(x * x)) : 1;
}

template <typename T>
constexpr T abs(T num) { return (num < 0) ? -num : num; }

template <typename Integer>
constexpr bool is_even(Integer num) {
  static_assert(std::is_integral<Integer>::value, "is_even is defined only for integer types");
  return num % 2 == 0;
}

template <typename T, typename Integer>
constexpr T pow(T a, Integer n) {
  static_assert(std::is_integral<Integer>::value, "pow supports only integral powers");
  return
  (n <  0) ? 1 / pow(a, -n)              :
  (n == 0) ? 1                           :
  (n == 1) ? a                           :
  (a == 2) ? 1LL << n                    :
  (is_even(n)) ? pow(a * a, n / 2)       :
  a * pow(a * a, (n - 1) / 2);
}

template <typename T>
constexpr T exp(T x) {
  return pow(constants<T>::e, floor<T, int>(x)) * exp_frac(x - floor<T, int>(x));
}

} // end namespace ConstMath
