// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cstdint>
#include <string>

#include "SF2Lib/IO/Pos.hpp"

/**
 Collection of types that mirror data structures defined in the SF2 spec. These are all read-only representations.
 */
namespace SF2::Entity {

/**
 Memory layout of a 'ibag/pbag' entry in a sound font resource. Used to access packed values from a
 resource. Per spec, the size of this must be 4. The wGenNdx and wModNdx properties contain the first index
 of the generator/modulator that belongs to the instrument/preset zone. The number of generator or
 modulator settings is found by subtracting index value of this instance from the index value of the
 subsequent instance. This is guaranteed to be safe in a well-formed SF2 file, as all collections that
 operate in this way have a terminating instance whose index value is the total number of generators or
 modulators in the preset or instrument zones.
 */
class Bag {
public:
  inline static const size_t entity_size = 4;

  /**
   Construct instance from values in file.

   @param pos location to read from
   */
  explicit Bag(IO::Pos& pos) noexcept;

  /// @returns first generator index in this collection
  size_t firstGeneratorIndex() const noexcept { return wGenNdx; }

  /// @returns number of generators in this collection
  size_t generatorCount() const noexcept {
    return (this + 1)->firstGeneratorIndex() - firstGeneratorIndex();
  }

  /// @returns first modulator index in this collection
  size_t firstModulatorIndex() const noexcept { return wModNdx; }

  /// @returns number of modulators in this collection
  size_t modulatorCount() const noexcept {
    return (this + 1)->firstModulatorIndex() - firstModulatorIndex();
  }

  /**
   Utility for displaying bag contents on output stream.

   @param indent the prefix to write out before each line
   @param index a prefix index value to write out before each lines
   */
  void dump(const std::string& indent, size_t index) const noexcept;

private:
  uint16_t wGenNdx;
  uint16_t wModNdx;
};

} // end namespace SF2::Entity
