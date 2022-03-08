// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Entity/Preset.hpp"

using namespace SF2::Entity;

void
Preset::dump(const std::string& indent, size_t index) const noexcept
{
  std::cout << indent << '[' << index << "] '" << name() << "' bank: " << bank() << " program: " << program()
  << " zoneIndex: " << firstZoneIndex() << " count: " << zoneCount() << std::endl;
}
