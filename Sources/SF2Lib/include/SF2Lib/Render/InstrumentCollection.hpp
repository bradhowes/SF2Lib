// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include <vector>

#include "SF2Lib/Render/Instrument.hpp"

namespace SF2::IO { class File; }
namespace SF2::Render {

/**
 Collection of all of the Entity::Instrument instances in an SF2 file, each of which is wrapped in a
 Render::Instrument instance for use during audio rendering.
 */
class InstrumentCollection
{
public:
  /**
   Construct a new collection using contents from the given file. Creates a new `Instrument` for each instrument definition in the
   file.

   @param file the file to build with
   */
  void build(IO::File& file) noexcept;

  /**
   Clear the collection of `Instrument` values but retain capacity.
   */
  void clear() noexcept;

  /**
   Obtain the (read-only) `Instrument` at the given index.

   @param index the index of the instrument to get
   @returns the `Instrument` reference
   */
  const Instrument& operator[](size_t index) const noexcept { return checkedVectorIndexing(instruments_, index); }

  /**
   Obtain the `Instrument` at the given index.

   @param index the index of the instrument to get
   @returns the `Instrument` reference
   */
  Instrument& operator[](size_t index) noexcept { return checkedVectorIndexing(instruments_, index); }

private:
  std::vector<Instrument> instruments_{};
};

} // namespace SF2::Render
