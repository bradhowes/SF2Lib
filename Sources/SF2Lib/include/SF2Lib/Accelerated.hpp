// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <concepts>
#include <Accelerate/Accelerate.h>

namespace SF2 {

/**
 Collection of function pointers that refer to routines found in Apple's Accelerated framework.
 These are written so that the right routine is chosen depending on the definition of `Float`.
 */
template <std::floating_point T>
struct Accelerated
{
  /**
   Type definition for vDSP\_vflt16 / vDSP\_vflt16D routines that convert a sequence of signed 16-bit integers into
   floating-point values. NOTE that this does not do any scaling of the resulting values.
   */
  using ConversionProc = void (*)(const int16_t*, vDSP_Stride, T*, vDSP_Stride, vDSP_Length);
  inline static ConversionProc conversionProc = []() noexcept {
    if constexpr (std::is_same_v<T, float>) return vDSP_vflt16;
    if constexpr (std::is_same_v<T, double>) return vDSP_vflt16D;
  }();

  /**
   Type definition for vDSP\_vsmul / vDSP\_vsmulD routines that multiplies a sequence of floating-point values by a
   scalar. This is used to obtain normalized values (-1.0 - +1.0) after converting from 16-bit integers to floats or
   doubles.
   */
  using ScaleProc = void (*)(const T*, vDSP_Stride, const T*, T*, vDSP_Stride, vDSP_Length);
  inline static ScaleProc scaleProc = []() noexcept {
    if constexpr (std::is_same_v<T, float>) return vDSP_vsmul;
    if constexpr (std::is_same_v<T, double>) return vDSP_vsmulD;
  }();

  /**
   Type definition for vDSP\_maxmgv / vDSP\_maxmgvD routines that calculate the max magnitude of a sequence of
   floating-point values.
   */
  using MagnitudeProc = void (*)(const T*, vDSP_Stride, T*, vDSP_Length);
  inline static MagnitudeProc magnitudeProc = []() noexcept {
    if constexpr (std::is_same_v<T, float>) return vDSP_maxmgv;
    if constexpr (std::is_same_v<T, double>) return vDSP_maxmgvD;
  }();
};

} // end namespace SF2
