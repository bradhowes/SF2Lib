// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <map>

#include "SF2Lib/IO/ChunkItems.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/NormalizedSampleSource.hpp"

namespace SF2::Render {

/**
 Collection of all of the SampleHeader entities from a SoundFont
 */
class SampleSourceCollection
{
public:
  using SampleHeader = Entity::SampleHeader;
  using Key = uint64_t;

  explicit SampleSourceCollection(const IO::ChunkItems<Entity::SampleHeader>& sampleHeaders) noexcept;

  void build(const SampleVector& normalizedSamples);

  const Voice::Sample::NormalizedSampleSource& operator[](size_t index) const;

private:

  Key makeKey(const SampleHeader& header) const noexcept;

  const IO::ChunkItems<Entity::SampleHeader>& sampleHeaders_;
  std::map<Key, Voice::Sample::NormalizedSampleSource> collection_;
};

}
