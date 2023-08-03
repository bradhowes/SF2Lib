// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <Accelerate/Accelerate.h>
#include <cmath>

namespace SF2 {

/**
 Type to use for all floating-point operations in SF2. For precision we do everything in 64-bit and convert at AUValue
 (32-bit float) only when necessary.
 */
using Float = double;

#ifndef __AVAudioTypes_h__
using AUValue = float;
using AUAudioFrameCount = uint32_t;
#else
using AUValue = ::AUValue;
using AUAudioFrameCount = ::AUAudioFrameCount;
#endif

/**
 Collection of function pointers that refer to routines found in Apple's Accelerated framework.
 These are written so that the right routine is chosen depending on the definition of `Float`.
 */
template <typename T>
struct Accelerated
{
  /**
   Type definition for vDSP_vflt16 / vDSP_vflt16D routines that convert a sequence of signed 16-bit integers into
   floating-point values.
   */
  using ConversionProc = void (*)(const int16_t*, vDSP_Stride, T*, vDSP_Stride, vDSP_Length);
  inline static ConversionProc conversionProc = []() noexcept {
    if constexpr (std::is_same_v<T, float>) return vDSP_vflt16;
    if constexpr (std::is_same_v<T, double>) return vDSP_vflt16D;
  }();

  /**
   Type definition for vDSP_vsdiv / vDSP_vsdivD routines that divide a sequence of floating-point values by a scalar.
   This is used to obtain normalized values (-1.0 - +1.0) after converting from 16-bit integers to floats or doubles.
   */
  using ScaleProc = void (*)(const T*, vDSP_Stride, const T*, T*, vDSP_Stride, vDSP_Length);
  inline static ScaleProc scaleProc = []() noexcept {
    if constexpr (std::is_same_v<T, float>) return vDSP_vsdiv;
    if constexpr (std::is_same_v<T, double>) return vDSP_vsdivD;
  }();

  /**
   Type definition for vDSP_maxmgv / vDSP_maxmgvD routines that calculate the max magnitude of a sequence of
   floating-point values.
   */
  using MagnitudeProc = void (*)(const T*, vDSP_Stride, T*, vDSP_Length);
  inline static MagnitudeProc magnitudeProc = []() noexcept {
    if constexpr (std::is_same_v<T, float>) return vDSP_maxmgv;
    if constexpr (std::is_same_v<T, double>) return vDSP_maxmgvD;
  }();
};

/**
 Generic method that invokes checked or unchecked indexing on a container based on the DEBUG compile flag. When DEBUG
 is defined, invokes `at` which will validate the index prior to use, and as a result is slower than just blindly
 indexing via `operator []`.
 */
template <typename T>
const typename T::value_type& checkedVectorIndexing(const T& container, size_t index) noexcept
{
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
  return container.at(index);
#else
  return container[index];
#endif
}

} // end namespace SF2
