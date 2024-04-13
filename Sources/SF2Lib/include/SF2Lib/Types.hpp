// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <AudioToolbox/AUParameters.h>
#include <cmath>
#include <concepts>
#include <vector>

namespace SF2 {

/**
 Type to use for all floating-point operations in SF2. For precision we do everything in 64-bit and convert at AUValue
 (32-bit float) only when necessary.
 */
using Float = double;
using SampleVector = std::vector<Float>;

#ifndef __AVAudioTypes_h__
using AUValue = float;
using AUAudioFrameCount = uint32_t;
#else
using AUValue = ::AUValue;
using AUAudioFrameCount = ::AUAudioFrameCount;
#endif

/// Concept that limits a type to a numeric type. NOTE: this might need to be refined.
template <typename T>
concept Numeric = std::floating_point<T> || std::integral<T>;

/// Concept that requires the type to be an enumeration.
template <typename T>
concept EnumeratedType = std::is_enum_v<T>;

/// Concept that requires the type to to be convertible to a `size_t` value.
template <typename T>
concept SizableType = std::convertible_to<T, std::size_t>;

/// Concept that requires the type to have an `entity_size` static member which provides a `size_t` value.
template <typename T>
concept EntityDerivedType = requires { { T::entity_size } -> std::convertible_to<std::size_t>; };

/// Concept that requires the type to support random access indexing. I think this can be improved on.
template <typename T>
concept RandomAccessContainer = requires(T v) { { v.at(0) } -> std::convertible_to<typename T::value_type>; };

/// Concept that requires the type to be an array of a fixed size and of type 'char'.
template <typename T>
concept CharArray = std::is_bounded_array_v<T> && requires(T v) { { v[0] } -> std::same_as<char&>; };

/**
 Generic method that invokes checked or unchecked indexing on a container based on the DEBUG compile flag. When DEBUG
 is defined, invokes `at` which will validate the index prior to use, and as a result is slower than just blindly
 indexing via `operator []`.
 */
template <RandomAccessContainer T>
const typename T::value_type& checkedVectorIndexing(const T& container, size_t index) noexcept
{
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
  return container.at(index);
#else
  return container[index];
#endif
}

/// Allow for safe indexing into a `vector` when enabled with `CHECKED_VECTOR_INDEXING` set to `1`.
template <RandomAccessContainer T, SizableType S>
const typename T::value_type& checkedVectorIndexing(const T& container, S index) noexcept
{
  auto index_ = static_cast<size_t>(index);
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
  return container.at(index_);
#else
  return container[index_];
#endif
}

template <RandomAccessContainer T, SizableType S>
typename T::value_type& checkedVectorIndexing(T& container, S index) noexcept
{
  auto index_ = static_cast<size_t>(index);
#if defined(CHECKED_VECTOR_INDEXING) && CHECKED_VECTOR_INDEXING == 1
  return container.at(index_);
#else
  return container[index_];
#endif
}

/// Literal operator that generates `Float` values from the literal content.
constexpr Float operator ""_F(long double value) { return Float(value); }
/// Literal operator that generates `Float` values from the literal content.
constexpr Float operator ""_F(unsigned long long value) { return Float(value); }

/**
 Convert an enum value into its underlying integral type.
 */
template <EnumeratedType T>
constexpr auto valueOf(T index) noexcept { return static_cast<typename std::underlying_type<T>::type>(index); }

/**
 Fixed-size array with template value type that can use an enum for indices.
 */
template <typename ElementType, EnumeratedType EnumType, size_t Size>
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
  inline typename super::const_reference operator[](EnumType index) const noexcept {
    return super::operator[](static_cast<size_t>(valueOf(index)));
  }

  inline typename super::const_reference operator[](size_t index) const noexcept {
    return super::operator[](index);
  }

  /**
   Obtain a reference to the value at the given index

   @param index the location of the value to return
   @returns an updatable reference for the given index
   */
  inline typename super::reference& operator[](EnumType index) noexcept {
    return super::operator[](static_cast<size_t>(valueOf(index)));
  }

  inline typename super::reference& operator[](size_t index) noexcept {
    return super::operator[](index);
  }
};

/**
 Convert a boolean value into an AUValue (float)

 @param value the value to convert
 @returns 1.0 for `true` and 0.0 for `false`
 */
inline static AUValue fromBool(bool value) noexcept { return value ? 1.0 : 0.0; }

/**
 Convert an AUValue (float) into a boolean value

 @param value the value to convert
 @returns 1.0 for `true` and 0.0 for `false`
 */
inline static bool toBool(AUValue value) noexcept { return value >= 0.5; }

} // end namespace SF2
