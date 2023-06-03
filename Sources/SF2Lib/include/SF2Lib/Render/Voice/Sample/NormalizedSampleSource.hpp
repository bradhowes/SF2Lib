// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>
#include <os/signpost.h>

#include <vector>

#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"

namespace SF2::Render::Voice::Sample {

/**
 Contains a collection of audio samples that range between -1.0 and 1.0. The values are derived from the
 16-bit values found in the SF2 file. Note that this conversion is done on-demand via the first call to
 `load`.
 */
class NormalizedSampleSource {
public:

  static constexpr Float normalizationScale = Float(1.0) / Float(1 << 15);
  static constexpr size_t sizePaddingAfterEnd = 46; // SF2 spec 7.10

  /**
   Construct a new normalized buffer of samples.

   @param samples pointer to the first 16-bit sample in the SF2 file
   @param header defines the range of samples to actually load
   */
  NormalizedSampleSource(const int16_t* samples, const Entity::SampleHeader& header) noexcept :
  samples_(header.endIndex() - header.startIndex() + sizePaddingAfterEnd), header_{header}, allSamples_{samples} {}

  /**
   Load the samples into buffer if not already available.
   */
  inline void load() const noexcept { if (!loaded_) loadNormalizedSamples<Float>(); }

  /// @returns true if the buffer is loaded
  bool isLoaded() const noexcept { return loaded_; }

  /// @returns number of samples in the canonical representation
  size_t size() const noexcept { return loaded_ ? samples_.size() : 0; }

  /// Unload the sample.
  void unload() const noexcept {
    loaded_ = false;
    samples_.clear();
  }

  /**
   Obtain the sample at the given index. Note that due to the copying of samples from the original stream, the indexing
   is correct from the standpoint of a Bounds instance.

   @param index the index to use
   @returns sample at the index
   */
  Float operator[](size_t index) const noexcept { return checkedVectorIndexing<decltype(samples_)>(samples_, index); }

  /// @returns the sample header ('shdr') of the sample stream being rendered
  const Entity::SampleHeader& header() const noexcept { return header_; }

private:

  template <typename T>
  void loadNormalizedSamples() const noexcept
  {
    assert(!loaded_);

    const size_t startIndex = header_.startIndex();
    const size_t size = header_.endIndex() - startIndex;
    samples_.resize(size + sizePaddingAfterEnd);

    // Read in the 16-bit sample values and convert into normalized values.
    auto pos = allSamples_ + header_.startIndex();
    constexpr T scale = (1 << 15);
    Accelerated<T>::conversionProc(pos, 1, samples_.data(), 1, size);
    Accelerated<T>::scaleProc(samples_.data(), 1, &scale, samples_.data(), 1, size);

    loaded_ = true;
  }

  using SampleVector = std::vector<Float>;

  mutable SampleVector samples_;
  const Entity::SampleHeader& header_;

  const int16_t* allSamples_;
  mutable bool loaded_{false};
  mutable Float noiseFloorOverMagnitude_;
  mutable Float noiseFloorOverMagnitudeOfLoop_;
};

} // namespace SF2::Render::Sample::Source
