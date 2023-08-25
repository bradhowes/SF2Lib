// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>
#include <unistd.h>

#include "SF2Lib/IO/Chunk.hpp"
#include "SF2Lib/Utils/StringUtils.hpp"

using namespace SF2::IO;

Chunk::Chunk(Tag tag, uint32_t size, Pos pos) noexcept :
tag_{tag},
size_{size},
pos_{pos}
{
  ;
}

std::string
Chunk::extract() const noexcept
{
  char buffer[256];
  size_t count = std::min(size(), sizeof(buffer));
  begin().readInto(buffer, count);
  buffer[count - 1] = 0;
  SF2::Utils::trim_property(buffer);
  return std::string(buffer);
}

void
Chunk::extractSamples(std::vector<int16_t>& buffer) const noexcept
{
  buffer.resize(size() / sizeof(int16_t), 0);
  begin().readInto(buffer.data(), size());
}
