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
