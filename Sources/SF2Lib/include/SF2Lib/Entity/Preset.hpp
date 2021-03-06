// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Entity/Entity.hpp"
#include "SF2Lib/IO/Chunk.hpp"
#include "SF2Lib/IO/Pos.hpp"
#include "SF2Lib/IO/StringUtils.hpp"

namespace SF2::Entity {

/**
 Memory layout of 'phdr' entry in sound font. The size of this is defined to be 38 bytes, but due
 to alignment/padding the struct below is 40 bytes.
 */
class Preset : Entity {
public:
  constexpr static size_t size = 38;
  
  /**
   Construct from contents of file.
   
   @param pos location to read from
   */
  explicit Preset(IO::Pos& pos) noexcept
  {
    assert(sizeof(*this) == size + 2);
    // Account for the extra padding by reading twice.
    pos = pos.readInto(&achPresetName, 20 + sizeof(uint16_t) * 3);
    pos = pos.readInto(&dwLibrary, sizeof(uint32_t) * 3);
    IO::trim_property(achPresetName);
  }
  
  /// @returns name of the preset
  char const* cname() const noexcept { return achPresetName; }
  std::string name() const noexcept { return achPresetName; }
  
  /// @returns preset number for this patch
  uint16_t program() const noexcept { return wPreset; }
  
  /// @returns bank number for the patch
  uint16_t bank() const noexcept { return wBank; }
  
  /// @returns the index of the first zone of the preset
  uint16_t firstZoneIndex() const noexcept { return wPresetBagNdx; }
  
  /// @returns the number of preset zones
  uint16_t zoneCount() const noexcept { return calculateSize(next(this).firstZoneIndex(), firstZoneIndex()); }
  
  void dump(const std::string& indent, size_t index) const noexcept;
  
private:
  
  char achPresetName[20];
  uint16_t wPreset;
  uint16_t wBank;
  uint16_t wPresetBagNdx;
  // *** PADDING ***
  uint32_t dwLibrary;
  uint32_t dwGenre;
  uint32_t dwMorphology;
};

} // end namespace SF2::Entity
