// Copyright © 2022 Brad Howes. All rights reserved.

#include <algorithm>
#include <cctype>
#include <locale>
#include <string>

#include "SF2Lib/Utils/StringUtils.hpp"

void
SF2::Utils::trim_property(char* property, size_t size) noexcept
{
  // This is really inefficient, but these sizes are very small (< 50) so...
  std::string s(property, size - 1);
  // Skip over spaces then remove from start to before first non-space
  s.erase(s.begin(), std::find_if(s.begin(), s.end(), [](int ch) { return ch != 0 && !std::isspace(ch); }));
  // Skip over all non-NULL, then erase everything after
  s.erase(std::find_if(s.begin(), s.end(), [](int ch) { return ch == 0; }), s.end());
  // Finally, sanitize any wacky characters
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) -> unsigned char {
    return std::isprint(c) ? c : '_';
  });
  // Move back to original container
  strncpy(property, s.c_str(), std::min(s.size() + 1, size));
}
