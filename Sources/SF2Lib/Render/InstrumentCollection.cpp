// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/InstrumentCollection.hpp"

using namespace SF2::Render;

void
InstrumentCollection::build(const SF2::IO::File& file) noexcept
{
  assert(instruments_.empty());
  const auto& definitions = file.instruments();
  auto count = definitions.size();
  instruments_.reserve(count);
  for (size_t index = 0; index < count; ++index) {
    instruments_.emplace_back(file, definitions[index]);
  }
}

void
InstrumentCollection::clear() noexcept
{
  instruments_.clear();
}

const Instrument&
InstrumentCollection::operator[](size_t index) const noexcept
{
  return checkedVectorIndexing(instruments_, index);
}
