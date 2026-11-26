// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <span>
#include <vector>

#include "SF2File/Entity/SampleHeader.hpp"

namespace SF2::IO {

/**
 Contains the span of samples that pertain to a specific MIDI key and velocity mapping. Samples remain in their native 16-bit
 representation until they are accessed.
 */
class NormalizedSampleSource {
public:
  static constexpr Float normalizationScale = 1.0_F / Float(1 << 15);
  static constexpr size_t sizePaddingAfterEnd = 46; // SF2 spec 7.10

  /**
   Construct a span of native 16-bit samples defined by a SampleHeader entity.

   @param samples collection of native 16-bit samples for a preset
   @param header defines the range of samples to actually load
   */
  NormalizedSampleSource(const SampleVector& samples, const Entity::SampleHeader& header) noexcept :
  header_{header},
  span_{
    std::ranges::next(samples.begin(), long(header.startIndex()), samples.end()),
    std::ranges::next(samples.begin(), long(header.endIndex() + sizePaddingAfterEnd), samples.end())
  }
  {}

  /// @returns number of samples in the canonical representation
  size_t size() const noexcept { return span_.size(); }

  /**
   Obtain the sample at the given index. Note that due to how the span of samples is defined, the indexing is zero-based and is
   correct from the standpoint of a Bounds instance.

   @param index the index to use
   @returns sample at the index
   */
  Float operator[](size_t index) const noexcept { return Float(span_[index]) * normalizationScale; }

  /// @returns the sample header ('shdr') of the sample stream being rendered
  const Entity::SampleHeader& header() const noexcept { return header_; }

private:
  const Entity::SampleHeader& header_;
  std::span<const int16_t> span_;
};

} // namespace SF2::IO
