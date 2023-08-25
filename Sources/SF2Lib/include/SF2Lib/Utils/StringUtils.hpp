// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

namespace SF2::Utils {

/**
 Remove spaces from start and end of a fixed character array. Replace non-printable characters with '_'.

 @param property location of text to clean up
 @param size the number of characters available in the character array
 */
void trim_property(char* property, size_t size) noexcept;

/**
 Templated version of the above -- only works with arrays.

 @param property reference to C++ array to work with
 */
template <typename T> static inline void trim_property(T& property) noexcept {
  trim_property(property, sizeof(property));
}

} // end namespace SF2::IO
