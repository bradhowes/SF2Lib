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
  static const size_t batchSampleCount = 40 * 1024;
  static const Float normalizationScale = 1.0_F / Float(1 << 15);

  size_t remainingSamples = size() / sizeof(int16_t);
  buffer.resize(remainingSamples);
  std::vector<int16_t> rawSamples(batchSampleCount);

  auto ptr = buffer.data();
  auto pos = begin();
  while (remainingSamples > 0) {
    auto sampleCount = std::min(remainingSamples, batchSampleCount);
    remainingSamples -= sampleCount;
    pos = pos.readInto(rawSamples.data(), sampleCount * sizeof(int16_t));
    Accelerated<Float>::conversionProc(rawSamples.data(), 1, ptr, 1, sampleCount);
    Accelerated<Float>::scaleProc(ptr, 1, &normalizationScale, ptr, 1, sampleCount);
    ptr += sampleCount;
  }
}
