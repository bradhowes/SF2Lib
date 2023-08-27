// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Entity/Preset.hpp"
#include "SF2Lib/IO/Pos.hpp"
#include "SF2Lib/Utils/StringUtils.hpp"

using namespace SF2::Entity;

Preset::Preset(IO::Pos& pos) noexcept
{
  // Account for the extra padding by reading twice.
  pos = pos.readInto(&achPresetName, 20 + sizeof(uint16_t) * 3);
  pos = pos.readInto(&dwLibrary, sizeof(uint32_t) * 3);
  SF2::Utils::trim_property(achPresetName);
}

Preset::Preset(uint16_t bank, uint16_t program) noexcept
:
wPreset{program},
wBank{bank},
wPresetBagNdx{},
dwLibrary{},
dwGenre{},
dwMorphology{}
{
  ;
}

size_t
Preset::zoneCount() const noexcept
{
  int value = (this + 1)->firstZoneIndex() - firstZoneIndex();
  return static_cast<size_t>(value);
}


void
Preset::dump(const std::string& indent, size_t index) const noexcept
{
  std::cout << indent << '[' << index << "] '" << name() << "' bank: " << bank() << " program: " << program()
  << " zoneIndex: " << firstZoneIndex() << " count: " << zoneCount() << std::endl;
}
