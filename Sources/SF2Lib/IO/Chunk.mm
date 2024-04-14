// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>
#include <unistd.h>
#include <vector>

#include "SF2Lib/IO/Chunk.hpp"
#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Utils/StringUtils.hpp"

using namespace SF2::IO;

Chunk::Chunk(Tag tag, uint32_t size, Pos pos) :
tag_{tag},
size_{size},
pos_{pos}
{
  auto available = pos.available();
  if (size > available) throw File::LoadResponse::invalidFormat;
}

std::string
Chunk::extract() const noexcept
{
  std::string buffer(size() + 1, char(0));
  begin().readInto(buffer.data(), size());
  buffer[size()] = 0;
  SF2::Utils::trim_property(buffer);
  return std::string(buffer);
}
