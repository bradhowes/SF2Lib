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

  explicit InstrumentCollection(const IO::File& file) noexcept { build(file); }

  /**
   Construct a new collection using contents from the given file.

   @param file the file to build with
   */
  void build(const IO::File& file) noexcept
  {
    auto count = file.instruments().size();
    instruments_.clear();
    if (count > instruments_.capacity()) instruments_.reserve(count);
    for (const Entity::Instrument& configuration : file.instruments().slice(0, count)) {
      instruments_.emplace_back(file, configuration);
    }
  }

  void clear() noexcept { instruments_.clear(); }

  const Instrument& operator[](size_t index) const noexcept { return checkedVectorIndexing(instruments_, index); }

private:
  std::vector<Instrument> instruments_{};
};

} // namespace SF2::Render
