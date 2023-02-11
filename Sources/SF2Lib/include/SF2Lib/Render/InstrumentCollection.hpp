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
  void build(const IO::File& file) noexcept
  {
    assert(instruments_.empty());
    const auto& definitions = file.instruments();
    auto count = definitions.size();
    instruments_.reserve(count);
    for (size_t index = 0; index < count; ++index) {
      instruments_.emplace_back(file, definitions[index]);
    }
  }

  void clear() noexcept { instruments_.clear(); }

  const Instrument& operator[](size_t index) const noexcept { return checkedVectorIndexing(instruments_, index); }

private:

  std::vector<Instrument> instruments_{};
};

} // namespace SF2::Render
