// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cstdint>
#include <string>

#include "SF2File/IO/Pos.hpp"

/**
 Collection of types that mirror data structures defined in the SF2 spec. These are all read-only representations.
 */
namespace SF2::Entity {

/**
 Memory layout of a 'ibag/pbag' entry in a sound font resource. Used to access packed values from a
 resource. Per spec, the size of this must be 4. The wGenNdx and wModNdx properties contain the first index
 of the generator/modulator that belongs to one instrument/preset zone. The number of generator or
 modulator settings is the difference between this record's index and the next record's (SF2.01 7.3, 7.7). Every
 list ends with a terminal record whose indices are the total number of generators and modulators.

 The counts are computed once by `ChunkItems` when the chunk is loaded (see `setCountsFrom`), so a copy of a `Bag`
 outside its container is self-contained. The terminal record's counts are 0.
 */
class Bag {
public:
  inline static const size_t entity_size = 4;

  /**
   Construct instance from values in file.

   @param pos location to read from
   */
  explicit Bag(IO::Pos& pos);

  /// @returns first generator index in this collection
  size_t firstGeneratorIndex() const noexcept { return wGenNdx; }

  /// @returns number of generators in this collection
  size_t generatorCount() const noexcept { return generatorCount_; }

  /// @returns first modulator index in this collection
  size_t firstModulatorIndex() const noexcept { return wModNdx; }

  /// @returns number of modulators in this collection
  size_t modulatorCount() const noexcept { return modulatorCount_; }

  /**
   Record the generator and modulator counts from the following bag record. A decreasing index gives 0 (`File`
   rejects such files).

   @param next the bag record that follows this one
   */
  void setCountsFrom(const Bag& next) noexcept {
    generatorCount_ = next.wGenNdx > wGenNdx ? uint16_t(next.wGenNdx - wGenNdx) : 0;
    modulatorCount_ = next.wModNdx > wModNdx ? uint16_t(next.wModNdx - wModNdx) : 0;
  }

  /**
   Utility for displaying bag contents on output stream.

   @param indent the prefix to write out before each line
   @param index a prefix index value to write out before each lines
   */
  void dump(const std::string& indent, size_t index) const;

private:
  uint16_t wGenNdx;
  uint16_t wModNdx;

  // Not part of the file record
  uint16_t generatorCount_{0};
  uint16_t modulatorCount_{0};
};

} // end namespace SF2::Entity
