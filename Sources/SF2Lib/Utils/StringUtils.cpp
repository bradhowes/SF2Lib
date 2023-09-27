// Copyright © 2022 Brad Howes. All rights reserved.

#include <algorithm>
#include <cctype>
#include <iostream>
#include <locale>
#include <string>

#include "SF2Lib/Utils/StringUtils.hpp"

void
SF2::Utils::trim_property(std::string& property) noexcept
{
  auto firstNotSpace = [](std::string::value_type ch) { return ch != 0 && !std::isspace(ch); };
  // Erase from front any whitespaces.
  property.erase(property.begin(), std::find_if(property.begin(), property.end(), firstNotSpace));

  // Skip over all non-NULL, then erase everything after
  auto firstNull = [](std::string::value_type ch) { return ch == 0; };
  property.erase(std::find_if(property.begin(), property.end(), firstNull), property.end());

  // Erase all spaces from end
  property.erase(std::find_if(property.rbegin(), property.rend(), firstNotSpace).base(), property.end());
  
  // Finally, sanitize any wacky characters
  std::transform(property.begin(), property.end(),
                 property.begin(), [](std::string::value_type c) { return std::isprint(c) ? c : '_'; });

  // std::cout << "trim_property - |" << property << "|\n";
}
