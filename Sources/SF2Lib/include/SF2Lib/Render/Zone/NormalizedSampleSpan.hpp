// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>

#include <memory>
#include <span>
#include <vector>

#include "SF2File/Entity/SampleHeader.hpp"

namespace SF2::Render::Zone {

/**
 Contains the span of native 16-bit samples that pertain to a specific MIDI key and velocity mapping.
 */
class NormalizedSampleSpan {
public:
  static constexpr Float normalizationScale = 1.0_F / Float(1 << 15);
  static constexpr size_t sizePaddingAfterEnd = 46; // SF2 spec 7.10

  /**
   Construct a span of native 16-bit samples defined by a SampleHeader entity.

   @param samples collection of native 16-bit samples for a `Preset`. It holds only the runs of the `smpl` chunk that the
   preset uses, packed together (see `Preset::loadSamples`), so file positions do not map directly onto it.
   @param firstIndex the index in `samples` of the header's first sample
   @param header defines the samples to use: `sampleSize()` samples plus `sizePaddingAfterEnd` padding samples
   */
  NormalizedSampleSpan(const SampleVector& samples, size_t firstIndex, const Entity::SampleHeader& header) noexcept :
  header_{header},
  span_{
    std::ranges::next(samples.begin(), long(firstIndex), samples.end()),
    std::ranges::next(samples.begin(), long(firstIndex + header.sampleSize() + sizePaddingAfterEnd), samples.end())
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
  int16_t operator[](size_t index) const noexcept { return span_[index]; }

  /// @returns the sample header ('shdr') of the sample stream being rendered
  const Entity::SampleHeader& header() const noexcept { return header_; }

private:
  const Entity::SampleHeader& header_;
  const std::span<const int16_t> span_;

  inline static const os_log_t log_{Log::create("NormalizedSampleSpan")};
};

} // namespace SF2::IO
