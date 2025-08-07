// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2File/Entity/Version.hpp"

using namespace SF2::Entity;

void
Version::dump(const std::string& indent) const noexcept
{
  std::cout << indent << "major: " << wMajor << " minor: " << wMinor << std::endl;
}
