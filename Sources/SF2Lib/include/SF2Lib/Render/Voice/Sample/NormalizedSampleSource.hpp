// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <vector>

#include "SF2Lib/Accelerated.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"

namespace SF2::Render::Voice::Sample {

/**
 Contains the set of audio samples that pertain to a MIDI key and velocity mapping. The samples come from the
 normalized vector of samples derived from 16-bit samples from the SF2 file. The range of samples contained in this
 collection is defined by the SampleHeader entity from the SF2 file. Per SF2 spec, there are 46 zeros following the
 samples.
 */
class NormalizedSampleSource {
public:
  inline static const Float normalizationScale = 1.0_F / Float(1 << 15);
  inline static const size_t sizePaddingAfterEnd = 46; // SF2 spec 7.10

  /**
   Construct a new normalized buffer of samples.

   @param samples pointer to the first 16-bit sample in the SF2 file
   @param header defines the range of samples to actually load
   */
  NormalizedSampleSource(const SampleVector& allSamples, const Entity::SampleHeader& header) noexcept :
  samples_{allSamples.begin() + header.startIndex(), allSamples.begin() + header.endIndex()}, header_{header}
  {
    // Append 46 zeros to end of the samples
    auto size = samples_.size() + sizePaddingAfterEnd;
    samples_.resize(size);
  }

  /// @returns number of samples in the canonical representation
  size_t size() const noexcept { return samples_.size(); }

  /**
   Obtain the sample at the given index. Note that due to the copying of samples from the original stream, the indexing
   is correct from the standpoint of a Bounds instance (zero-based).

   @param index the index to use
   @returns sample at the index
   */
  inline Float operator[](size_t index) const noexcept {
    return checkedVectorIndexing<decltype(samples_)>(samples_, index);
  }

  /// @returns the sample header ('shdr') of the sample stream being rendered
  const Entity::SampleHeader& header() const noexcept { return header_; }

private:
  SampleVector samples_;
  const Entity::SampleHeader& header_;
};

} // namespace SF2::Render::Sample::Source
