// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <cstring>
#include <string>

#include "DSPHeaders/Concepts.hpp"
#include "SF2Util/Types.hpp"

namespace SF2::Utils {

/**
 Remove spaces from start and end of a std::string. Replace non-printable characters with '_'.

 @param property location of text to clean up
 */
void trim_property(std::string& property) noexcept;

/**
 Templated version of the above -- only works with arrays.

 @param property reference to C++ array to work with
 */
template <DSPHeaders::CharArray T>
static void trim_property(T& property) {
  auto size = sizeof(T);
  std::string s(property, size);
  trim_property(s);
  memset(property, 0, size);
  // Always leave room for a terminating NUL: SF2 names fill the whole array when they are 20 characters long.
  memcpy(property, s.data(), std::min(s.size(), size - 1));
}

} // end namespace SF2::IO
