// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>

#include <memory>
#include <span>
#include <vector>

#include "SF2File/Entity/SampleHeader.hpp"

namespace SF2::Render::Zone {

/**
 Contains the span of samples that pertain to a specific MIDI key and velocity mapping. The samples come from the normalized vector
 of samples derived from 16-bit samples from the SF2 file.
 */
class NormalizedSampleSpan {
public:
  inline static constexpr Float normalizationScale = 1.0_F / Float(1 << 15);
  inline static constexpr size_t sizePaddingAfterEnd = 46; // SF2 spec 7.10

  /**
   Construct a span of normalized samples defined by a SampleHeader entity.

   @param samples collection of normalized samples for a `Preset`
   @param offset the offset of the first sample in terms of the SF2 file.
   @param header defines the range of samples to actually load. The start/end values must be adjusted by `zeroOffset` before being
   used to index into `samples`.
   */
  NormalizedSampleSpan(const SampleVector& samples, size_t offset, const Entity::SampleHeader& header) noexcept :
  header_{header},
  span_{
    std::ranges::next(samples.begin(), long(header.startIndex() - offset), samples.end()),
    std::ranges::next(samples.begin(), long(header.endIndex() + sizePaddingAfterEnd - offset), samples.end())
  }
  {
    auto startPos = header.startIndex() - offset;
    auto endPos = header.endIndex() - offset;
    os_log_debug(log_, "init - offset: %ld spanStart: %ld spanEnd: %ld (%ld)", offset, startPos, endPos, endPos - startPos);
    os_log_debug(log_, "init - samples.size: %ld span.size: %ld", samples.size(), span_.size());
    os_log_debug(log_, "init - first: %f", span_[0]);
    auto p = &span_[endPos - startPos];
    os_log_debug(log_, "init - last: %f %f %f %f %f %f %f %f %f %f",
                 p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9]);
  }

  /// @returns number of samples in the canonical representation
  inline size_t size() const noexcept { return span_.size(); }

  /**
   Obtain the sample at the given index. Note that due to how the span of samples is defined, the indexing is zero-based and is
   correct from the standpoint of a Bounds instance.

   @param index the index to use
   @returns sample at the index
   */
  inline Float operator[](size_t index) const noexcept { return span_[index]; }

  /// @returns the sample header ('shdr') of the sample stream being rendered
  inline const Entity::SampleHeader& header() const noexcept { return header_; }

private:
  const Entity::SampleHeader& header_;
  const std::span<const Float> span_;

  inline static const os_log_t log_{Log::create("NormalizedSampleSpan")};
};

} // namespace SF2::IO
