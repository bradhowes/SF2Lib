// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>

namespace SF2::ConstMath {

/// If type of template argument is an integral type, use `double` type. Otherwise, the template arg.
template<typename T>
using IntegralAsDouble = typename std::conditional_t<std::is_integral_v<T>, double, T>;

/// Identify the common type for the given template arguments.
template<typename ...T>
using CommonType = typename std::common_type_t<T...>;

/// If common type is an integral type, use `double` type. Otherwise, the common type.
template<typename ...T>
using CommonIntegralAsDouble = IntegralAsDouble<CommonType<T...>>;

// Based on work from https://github.com/lakshayg/compile_time

template <typename T>
struct Constants {
  static constexpr T e = T(2.7182818284590452353602874713526624977572L);
  static constexpr T ln2 = T(0.6931471805599453094172321214581765680755L);
  static constexpr T ln10 = T(2.3025850929940456840179914546843642076011L);
  static constexpr T PI = T(3.1415926535897932384626433832795028841972L);
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
constexpr T squared(T x) noexcept { return x * x; }

namespace detail {

template <typename T>
constexpr T normalizedRadians(T theta) noexcept {
  T PI = Constants<T>::PI;
  return (theta <= -PI) ? normalizedRadians(theta + PI * 2) : (theta > PI) ? normalizedRadians(theta - PI * 2) : theta;
}

template <typename Real>
constexpr Real sin_cfrac(Real x2, int k = 2, int n = 40) {
  return (n == 0) ? k * (k + 1) - x2
  : k * (k + 1) - x2 +
  (k * (k + 1) * x2) / sin_cfrac(x2, k + 2, n - 1);
}

template <typename Real>
constexpr Real tan_cfrac(Real x2, int k = 1, int n = 40) {
  return (n == 0) ? k : k - x2 / tan_cfrac(x2, k + 2, n - 1);
}

template <typename Real>
constexpr Real fast_atan_unit(Real x) {  // -1 <= x <= 1
  return Constants<Real>::QuarterPI * x - x * (abs(x) - 1) * (0.2447 + 0.0663 * abs(x));
}

template <typename Real>
constexpr Real exp_frac_helper(Real x2, int iter = 5, int k = 6) {
  return (iter > 0) ? k + x2 / exp_frac_helper(x2, iter - 1, k + 4) : k + x2 / (k + 4);
}

template <typename Real>
constexpr Real exp_frac(Real x) {
  return (x != 0) ? 1 + 2 * x / (2 - x + (x * x) / exp_frac_helper(x * x)) : 1;
}

}  // namespace detail

template <typename Real>
constexpr Real sin(Real x) {
  return detail::normalizedRadians(x) /
  (1 + squared(detail::normalizedRadians(x)) / detail::sin_cfrac(squared(detail::normalizedRadians(x))));
}

template <typename Real>
constexpr Real cos(Real x) {
  return sin(Constants<Real>::HalfPI - x);
}

template <typename Real, typename Integer = long long>
constexpr Integer floor(Real x) {
  static_assert(std::is_floating_point_v<Real>, "floor accepts only floating point inputs");
  return static_cast<Integer>(x) - (static_cast<Integer>(x) > x);
}

template <typename Real, typename Integer = long long>
constexpr Integer ceil(Real x) {
  if constexpr (std::is_integral_v<Real>) { return static_cast<Integer>(x); }
  return static_cast<Integer>(x) + (static_cast<Integer>(x) < x);
}

template <typename T>
constexpr T abs(T num) { return (num < 0) ? -num : num; }

template <typename Integer>
constexpr bool is_even(Integer num) {
  static_assert(std::is_integral_v<Integer>, "is_even is defined only for integer types");
  return num % 2 == 0;
}

template <typename Real, typename Integer>
constexpr Real pow(Real a, Integer n) {
  static_assert(std::is_integral_v<Integer>, "pow supports only integral powers");
  return
  (n <  0) ? 1 / pow(a, -n)              :
  (n == 0) ? 1                           :
  (n == 1) ? a                           :
  (a == 2) ? 1LL << n                    :
  (is_even(n)) ? pow(a * a, n / 2)       :
  a * pow(a * a, (n - 1) / 2);
}

template <typename Real>
constexpr Real exp(Real x) {
  return pow(Constants<Real>::e, floor(x)) * detail::exp_frac(x - floor(x));
}

template <typename Real, typename Integer>
constexpr Integer ilog(Real x, Real b) {
  return (b == 1) ? throw std::domain_error("base == 1") :
  (b <= 0) ? throw std::domain_error("base <= 0")  :
  (x <= 0) ? throw std::domain_error("x <= 0")     :
  (x >= b) ? ilog(x / b, b) + 1                   :
  (x < 1 ) ? ilog(b * x, b) - 1                   :
  0;
}

} // end namespace ConstMath
