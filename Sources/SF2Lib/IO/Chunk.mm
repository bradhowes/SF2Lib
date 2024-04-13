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

void
Chunk::extractNormalizedSamples(SampleVector& buffer) const noexcept
{
  static const Float normalizationScale = 1.0_F / Float(1 << 15);
  std::vector<int16_t> rawSamples;
  rawSamples.resize(size() / sizeof(int16_t), 0);

  begin().readInto(rawSamples.data(), size());

  buffer.resize(rawSamples.size(), 0.0_F);
  Accelerated<Float>::conversionProc(rawSamples.data(), 1, buffer.data(), 1, rawSamples.size());
  Accelerated<Float>::scaleProc(buffer.data(), 1, &normalizationScale, buffer.data(), 1, buffer.size());
}
