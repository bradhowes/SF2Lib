// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/IO/Pos.hpp"

namespace SF2::Entity {

/**
 Memory layout of 'phdr' entry in sound font. The size of this is defined to be 38 bytes, but due
 to alignment/padding the struct below is 40 bytes.
 */
class Preset {
public:
  inline static const size_t entity_size = 38;

  /**
   Construct from contents of file.

   @param pos location to read from
   */
  explicit Preset(IO::Pos& pos) noexcept;

  /**
   Construct a pseudo-Preset that is only used to locate a Preset in a file.

   @param bank the bank to look in
   @param program the program to locate in the given bank
   */
  Preset(uint16_t bank, uint16_t program) noexcept;

  /// @returns name of the preset
  char const* cname() const noexcept { return achPresetName; }

  /// @returns name of the preset
  std::string name() const noexcept { return achPresetName; }

  /// @returns preset number for this patch
  uint16_t program() const noexcept { return wPreset; }

  /// @returns bank number for the patch
  uint16_t bank() const noexcept { return wBank; }

  /// @returns the index of the first zone of the preset
  size_t firstZoneIndex() const noexcept { return wPresetBagNdx; }

  uint32_t library() const noexcept { return dwLibrary; }

  uint32_t genre() const noexcept { return dwGenre; }

  uint32_t morphology() const noexcept { return dwMorphology; }

  /// @returns the number of preset zones
  size_t zoneCount() const noexcept {
    return (this + 1)->firstZoneIndex() - firstZoneIndex();
  }

  /// Write out description of the preset to std::cout
  void dump(const std::string& indent, size_t index) const noexcept;

  /// @returns true if first argument is ordered lower than the second
  friend bool operator<(const Preset& lhs, const Preset& rhs) noexcept {
    return lhs.bank() < rhs.bank() || (lhs.bank() == rhs.bank() && lhs.program() < rhs.program());
  }

  /// @returns true if first argument has same bank/program pair as second
  friend bool operator==(const Preset& lhs, const Preset& rhs) noexcept {
    return lhs.bank() == rhs.bank() && lhs.program() == rhs.program();
  }

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
