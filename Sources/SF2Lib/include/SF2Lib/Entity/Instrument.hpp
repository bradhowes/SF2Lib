// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Entity/Entity.hpp"
#include "SF2Lib/IO/Pos.hpp"
#include "SF2Lib/IO/StringUtils.hpp"

namespace SF2::Entity {

/**
 Memory layout of a 'inst' entry. The size of this is defined to be 22 bytes.
 
 An `instrument` is ultimately defined by its samples, but there can be multiple instruments defined that use the same
 sample source with different gen/mod settings (the sample source is indeed itself a generator setting).
 */
class Instrument : Entity {
public:
  constexpr static size_t size = 22;
  
  explicit Instrument(IO::Pos& pos) noexcept {
    assert(sizeof(*this) == size);
    pos = pos.readInto(*this);
    IO::trim_property(achInstName);
  }
  
  /// @returns the name of the instrument
  std::string name() const noexcept { return std::string(achInstName); }
  
  /// @returns the index of the first Zone of the instrument
  uint16_t firstZoneIndex() const noexcept { return wInstBagNdx; }
  
  /// @returns the number of instrument zones
  uint16_t zoneCount() const noexcept { return calculateSize(next(this).firstZoneIndex(), firstZoneIndex()); }
  
  void dump(const std::string& indent, size_t index) const noexcept;
  
private:
  char achInstName[20];
  uint16_t wInstBagNdx;
};

} // end namespace SF2::Entity
