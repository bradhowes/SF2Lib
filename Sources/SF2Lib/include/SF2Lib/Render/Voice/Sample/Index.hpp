// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include <limits>
#include <utility>

#include "SF2File/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"

namespace SF2::Render::Voice::Sample {

/**
 Interpolatable index into a `NormalizedSamples` collection. Maintains two counters, an integral one (`size_t`) and a
 partial one (`Float`) that indicates how close the index is to a sample index. These two values are then used by other
 routines to fetch the appropriate samples and interpolate over them. (FluidSynth uses two 32-bit integers to do the same.)

 Updates to the index honor loops in the sample stream if allowed. The index can also signal when it has reached the
 end of the sample stream via its `finished` method.
 */
class Index {
public:
  /**
   Configure the index to work with the given bounds.

   @param bounds the sample bounds to work with
   */
  void configure(const Bounds& bounds) noexcept { bounds_ = bounds; }

  /// Start rendering.
  void start() noexcept {
    whole_ = 0;
    partial_ = 0_F;
    looped_ = false;
  }

  /// Signal that no further rendering will take place using this index until a new start.
  void stop() noexcept { whole_ = bounds_.endPos(); }

  /// @returns true if the index has been stopped.
  inline bool finished() const noexcept { return whole_ >= bounds_.endPos(); }

  /// @returns true if the index has looped.
  inline bool looped() const noexcept { return looped_; }

  /**
   Increment the index to the next location. Properly handles looping and buffer end.

   @param increment the increment to apply to the internal index
   @param canLoop true if looping is allowed
   */
  inline void increment(Float increment, bool canLoop) noexcept {
    if (finished()) return;

    auto wholeIncrement{size_t(increment)};
    auto partialIncrement{increment - wholeIncrement};

    whole_ += wholeIncrement;
    partial_ += partialIncrement;

    if (partial_ >= 1_F) {
      auto carry{trunc(partial_)};
      whole_ += size_t(carry);
      partial_ -= carry;
    }

    if (canLoop && bounds_.hasLoop() && whole_ >= bounds_.endLoopPos()) {
      whole_ -= bounds_.loopSize();
      looped_ = true;
    }
    else if (whole_ >= bounds_.endPos()) {
      stop();
    }
  }

  /// @returns index to first sample to use for rendering
  inline size_t whole() const noexcept { return whole_; }

  /// @returns normalized position between 2 samples. For instance, 0.5 indicates half-way between two samples.
  inline Float partial() const noexcept { return partial_; }

private:
  size_t whole_{0};
  Float partial_{0_F};
  Bounds bounds_{};
  bool looped_{false};
};

} // namespace Sf2::Render::Sample
