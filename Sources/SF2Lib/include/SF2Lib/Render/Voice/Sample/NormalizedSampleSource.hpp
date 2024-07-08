// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <span>
#include <vector>

#include "SF2Lib/Accelerated.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"

namespace SF2::Render::Voice::Sample {

/**
 Contains the span of samples that pertain to a specific MIDI key and velocity mapping.
 The samples come from the normalized vector of samples derived from 16-bit samples from
 the SF2 file.
 */
class NormalizedSampleSource {
public:
  inline static const Float normalizationScale = 1.0_F / Float(1 << 15);
  inline static const size_t sizePaddingAfterEnd = 46; // SF2 spec 7.10

  /**
   Construct a span of normalized samples defined by a SampleHeader entity.

   @param allSamples collection of normalized samples in the SF2 file
   @param header defines the range of samples to actually load
   */
  NormalizedSampleSource(const SampleVector& allSamples, const Entity::SampleHeader& header) noexcept :
  header_{header},
  span_(std::ranges::next(allSamples.begin(), long(header.startIndex())),
        std::ranges::next(allSamples.begin(), long(header.endIndex() + sizePaddingAfterEnd)))
  {
  }

  /// @returns number of samples in the canonical representation
  size_t size() const noexcept { return span_.size(); }

  /**
   Obtain the sample at the given index. Note that due to how the span of samples is 
   defined, the indexing iz zero-based and is correct from the standpoint of a Bounds
   instance.

   @param index the index to use
   @returns sample at the index
   */
  inline Float operator[](size_t index) const noexcept { return span_[index]; }

  /// @returns the sample header ('shdr') of the sample stream being rendered
  const Entity::SampleHeader& header() const noexcept { return header_; }

private:
  const Entity::SampleHeader& header_;
  const std::span<const Float> span_;
};

} // namespace SF2::Render::Sample::Source
