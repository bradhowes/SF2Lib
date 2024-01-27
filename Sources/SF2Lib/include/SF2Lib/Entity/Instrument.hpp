// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/IO/Pos.hpp"

namespace SF2::Entity {

/**
 Memory layout of a 'inst' entry. The size of this is defined to be 22 bytes.

 An `instrument` is ultimately defined by its samples, but there can be multiple instruments defined that use the same
 sample source with different gen/mod settings (the sample source is indeed itself a generator setting).
 */
class Instrument {
public:
  inline static const size_t entity_size = 22;

  /**
   Construct from file.

   @param pos location in file to read
   */
  explicit Instrument(IO::Pos& pos) noexcept;

  /// @returns the name of the instrument
  std::string name() const noexcept;

  /// @returns the index of the first Zone of the instrument
  size_t firstZoneIndex() const noexcept { return wInstBagNdx; }

  /// @returns the number of instrument zones
  size_t zoneCount() const noexcept {
    return (this + 1)->firstZoneIndex() - firstZoneIndex();
  }

  void dump(const std::string& indent, size_t index) const noexcept;

private:
  char achInstName[20];
  uint16_t wInstBagNdx;
};

} // end namespace SF2::Entity
