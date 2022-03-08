// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Entity/Instrument.hpp"

using namespace SF2::Entity;

void
Instrument::dump(const std::string& indent, size_t index) const noexcept
{
  std::cout << indent << '[' << index << "] '" << name() << "' zoneIndex: " << firstZoneIndex()
  << " count: " << zoneCount() << std::endl;
}
