// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <string>

#include "SF2Lib/Types.hpp"

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
template <CharArray T> static inline void trim_property(T& property) noexcept {
  auto size = sizeof(T);
  std::string s(property, size);
  trim_property(s);
  memset(property, 0, size);
  memcpy(property, s.data(), s.size());
}

} // end namespace SF2::IO
