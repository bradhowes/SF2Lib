// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/IO/Pos.hpp"
#include "SF2Lib/Entity/Instrument.hpp"
#include "SF2Lib/Utils/StringUtils.hpp"

using namespace SF2::Entity;

Instrument::Instrument(IO::Pos& pos) noexcept
{
  pos = pos.readInto(*this);
  SF2::Utils::trim_property(achInstName);
}

std::string
Instrument::name() const noexcept
{
  return std::string(achInstName);
}

void
Instrument::dump(const std::string& indent, size_t index) const noexcept
{
  std::cout << indent << '[' << index << "] '" << name() << "' zoneIndex: " << firstZoneIndex()
  << " count: " << zoneCount() << std::endl;
}
