// Copyright © 2022 Brad Howes. All rights reserved.

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

  InstrumentCollection() = default;

  /**
   Construct a new collection using contents from the given file.

   @param file the file to build with
   */
  void build(IO::File& file) noexcept;

  void clear() noexcept;

  const Instrument& operator[](size_t index) const noexcept;

private:
  std::vector<Instrument> instruments_{};
};

} // namespace SF2::Render
