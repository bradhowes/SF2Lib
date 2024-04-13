// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/SampleSourceCollection.hpp"

using namespace SF2::Render;

SampleSourceCollection::SampleSourceCollection(const SF2::IO::ChunkItems<Entity::SampleHeader>& sampleHeaders) noexcept
: sampleHeaders_{sampleHeaders}
{
  ;
}

void
SampleSourceCollection::build(const SampleVector& normalizedSamples)
{
  for (const auto& header : sampleHeaders_) {
    auto key{makeKey(header)};
    auto found = collection_.find(key);
    if (found == collection_.end()) {
      auto [it, ok] = collection_.emplace(key, Voice::Sample::NormalizedSampleSource{normalizedSamples, header});
      if (!ok) throw std::runtime_error("failed to insert sample source");
    }
  }
}

const Voice::Sample::NormalizedSampleSource&
SampleSourceCollection::operator[](size_t index) const
{
  const auto& header = sampleHeaders_[index];
  auto found = collection_.find(makeKey(header));
  if (found == collection_.end()) throw std::runtime_error("failed to locate sample source");
  return found->second;
}

SampleSourceCollection::Key
SampleSourceCollection::makeKey(const SampleHeader& header) const noexcept
{
  return static_cast<Key>(header.startIndex()) << 32 | static_cast<Key>(header.endIndex());
}

