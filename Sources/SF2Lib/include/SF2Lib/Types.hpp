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

template <typename T>
typename T::value_type& checkedVectorIndexing(T& container, size_t index) noexcept
{
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
  return container.at(index);
#else
  return container[index];
#endif
}

constexpr Float operator ""_F(long double value) { return Float(value); }
constexpr Float operator ""_F(unsigned long long value) { return Float(value); }

/**
 Convert an enum value into its underlying integral type.
 */
template <typename T>
inline auto valueOf(T index) noexcept { return static_cast<typename std::underlying_type<T>::type>(index); }

/**
 Fixed-size array with template value type that can use an enum for indices.
 */
template <typename ElementType, typename EnumType, size_t Size>
class EnumIndexableValueArray : public std::array<ElementType, Size>
{
  using super = std::array<ElementType, Size>;

public:

  /**
   Set all values in the array to the default value for the template type.
   */
  void zero() { this->fill(ElementType()); }

  /**
   Obtain the value at the given index

   @param index the location of the value to return
   @returns the value at the give index
   */
  typename super::const_reference operator[](EnumType index) const noexcept {
    return super::operator[](static_cast<size_t>(valueOf(index)));
  }

  typename super::const_reference operator[](size_t index) const noexcept {
    return super::operator[](index);
  }

  /**
   Obtain a reference to the value at the given index

   @param index the location of the value to return
   @returns an updatable reference for the given index
   */
  typename super::reference& operator[](EnumType index) noexcept {
    return super::operator[](static_cast<size_t>(valueOf(index)));
  }

  typename super::reference& operator[](size_t index) noexcept {
    return super::operator[](index);
  }
};

} // end namespace SF2
