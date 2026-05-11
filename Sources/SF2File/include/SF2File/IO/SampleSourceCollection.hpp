// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <vector>

#include "SF2File/IO/ChunkItems.hpp"
#include "SF2File/Entity/SampleHeader.hpp"
#include "SF2File/IO/NormalizedSampleSource.hpp"

namespace SF2::IO {

/**
 Collection of all of the SampleHeader entities from a SoundFont paired with a span of normalized samples to use when
 rendering. Does not hold the actual samples themselves.
 */
class SampleSourceCollection
{
public:
  SampleSourceCollection() noexcept = default;

  /**
   Construct the collection of NormalizedSampleSource values from the given ones.

   @param normalizedSamples all of the samples in normalized form from the SF2 file
   @param sampleHeaders all of the SampleHeader entities from the SF2 file
   */
  void build(const SampleVector& normalizedSamples, const IO::ChunkItems<Entity::SampleHeader>& sampleHeaders) {
    for (const auto& header : sampleHeaders) {
      collection_.emplace_back(normalizedSamples, header);
    }
  }

  /// @return the NormalizedSampleSource value at the given index, where the index comes from the instrument definition in the SF2
  /// file.
  const NormalizedSampleSource& operator[](size_t index) const {
    return checkedVectorIndexing(collection_, index);
  }

  /// @return true if the collection is empty. This is true after File loading due to lazy-loading of the rendering
  /// entities such as this.
  bool empty() const noexcept { return collection_.empty(); }

private:
  std::vector<NormalizedSampleSource> collection_{};
};

}
