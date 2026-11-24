// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2File/IO/Pos.hpp"

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
  explicit Instrument(IO::Pos& pos);

  /// @returns the name of the instrument
  std::string name() const;

  /// @returns the index of the first Zone of the instrument
  size_t firstZoneIndex() const noexcept { return wInstBagNdx; }

  /// @returns the number of instrument zones. Set by `ChunkItems` when the INST chunk is loaded (0 for the terminal
  /// record).
  size_t zoneCount() const noexcept { return zoneCount_; }

  /**
   Record the number of zones from the following INST record. SF2.01 7.6: the zones of an instrument run up to the next
   instrument's `wInstBagNdx`. A decreasing index gives 0 (`File` rejects such files).

   @param next the INST record that follows this one
   */
  void setCountsFrom(const Instrument& next) noexcept {
    zoneCount_ = next.wInstBagNdx > wInstBagNdx ? uint16_t(next.wInstBagNdx - wInstBagNdx) : 0;
  }

  void dump(const std::string& indent, size_t index) const;

private:
  char achInstName[20];
  uint16_t wInstBagNdx;

  // Not part of the file record
  uint16_t zoneCount_{0};
};

} // end namespace SF2::Entity
