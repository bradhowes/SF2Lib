// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>

#include <span>
#include <vector>

#include "SF2File/Entity/SampleHeader.hpp"

namespace SF2::Render::Zone {

/**
 Contains the span of samples that pertain to a specific MIDI key and velocity mapping. The samples come from the normalized vector
 of samples derived from 16-bit samples from the SF2 file.
 */
class NormalizedSamples {
public:
  inline static constexpr Float normalizationScale = 1.0_F / Float(1 << 15);
  inline static constexpr size_t sizePaddingAfterEnd = 46; // SF2 spec 7.10

  /**
   Construct a span of normalized samples defined by a SampleHeader entity.

   @param samples collection of normalized samples for a `Preset`
   @param zeroOffset the offset of the first sample in terms of the SF2 file.
   @param header defines the range of samples to actually load. The start/end values must be adjusted by `zeroOffset` before being
   used to index into `samples`.
   */
  NormalizedSamples(const SampleVector& samples, size_t zeroOffset, const Entity::SampleHeader& header) noexcept :
  span_(std::ranges::next(samples.begin(), long(header.startIndex() - zeroOffset)),
        std::ranges::next(samples.begin(), long(header.endIndex() + sizePaddingAfterEnd - zeroOffset))),
  header_{header}
  {
    os_log_debug(log_, "init - zeroOffset: %ld spanStart: %ld spanEnd: %ld",
                 zeroOffset, header.startIndex() - zeroOffset, header.endIndex() + sizePaddingAfterEnd - zeroOffset);
  }

  /// @returns number of samples in the canonical representation
  inline size_t size() const noexcept { return span_.size(); }

  /**
   Obtain the sample at the given index. Note that due to how the span of samples is defined, the indexing is zero-based and is
   correct from the standpoint of a Bounds instance.

   @param index the index to use
   @returns sample at the index
   */
  inline Float operator[](size_t index) const noexcept {
    return checkedVectorIndexing(index);
  }

  /// @returns the sample header ('shdr') of the sample stream being rendered
  inline const Entity::SampleHeader& header() const noexcept { return header_; }

private:

  inline Float checkedVectorIndexing(size_t index) const noexcept {
#if CHECKED_VECTOR_INDEXING == 1
    assert(index < span_.size());
    return span_[index];
#else
    return span_[index];
#endif
  }

  const std::span<const Float> span_;
  const Entity::SampleHeader& header_;

  inline static const os_log_t log_{Log::create("NormalizedBounds")};
};

} // namespace SF2::IO
