// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <map>

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

  explicit SampleSourceCollection(const IO::ChunkItems<Entity::SampleHeader>& sampleHeaders) noexcept
  : sampleHeaders_{sampleHeaders}
  {
    
  }

  void build(const int16_t* rawSamples)
  {
    for (const auto& header : sampleHeaders_) {
      auto key{makeKey(header)};
      auto found = collection_.find(key);
      if (found == collection_.end()) {
        auto [it, ok] = collection_.emplace(key, Voice::Sample::NormalizedSampleSource{rawSamples, header});
        if (!ok) throw std::runtime_error("failed to insert sample source");
      }
    }
  }


  const Voice::Sample::NormalizedSampleSource& operator[](size_t index) const
  {
    const auto& header = sampleHeaders_[index];
    auto found = collection_.find(makeKey(header));
    if (found == collection_.end()) throw std::runtime_error("failed to locate sample source");
    return found->second;
  }

private:

  Key makeKey(const SampleHeader& header) const noexcept {
    return static_cast<Key>(header.startIndex()) << 32 | static_cast<Key>(header.endIndex());
  }

  const IO::ChunkItems<Entity::SampleHeader>& sampleHeaders_;
  std::map<Key, Voice::Sample::NormalizedSampleSource> collection_;
};

}
