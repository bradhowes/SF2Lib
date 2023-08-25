// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <string>

#include <algorithm>
#include <cctype>
#include <locale>

namespace SF2::Utils {

void trim_property(char* property, size_t size) noexcept;

template <typename T> static inline void trim_property(T& property) noexcept {
  trim_property(property, sizeof(property));
}

} // end namespace SF2::IO
