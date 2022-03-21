// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <limits>
#include <utility>

#include "SF2Lib/Logger.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"

namespace SF2::Render::Voice::Sample {

/**
 Interpolatable index into a NormalizedSampleSource. Maintains two counters, an integral one (size_t) and a partial
 one (double) that indicates how close the index is to a sample index. These two values are then used by SampleBuffer
 routines to fetch the correct samples and interpolate over them.

 Updates to the index honor loops in the sample stream if allowed. The index can also signal when it has reached the
 end of the sample stream via its `finished` method.
 */
class Index {
  struct State;
public:

  /**
   Construct new instance. NOTE: the instance is not usable for audio rendering at this point. One must call
   `configure` in order to be useable for rendering purposes.
   */
  Index() = default;

  /**
   Configure the index to work with the given bounds. NOTE: this is invoked before start of rendering a note. This
   routine *must* ensure that the state is properly setup to do so, just as if it was created from scratch.

   @param bounds the sample bounds to work with
   */
  void configure(Bounds bounds) noexcept {
    state_ = State(std::forward<Bounds>(bounds));
  }

  /// Signal that no further operations will take place using this index.
  void stop() noexcept { state_.stop(); }

  /// @returns true if the index has been stopped.
  bool finished() const noexcept { return state_.whole_ >= state_.bounds_.endPos(); }

  /// @returns true if the index has looped.
  bool looped() const noexcept { return state_.looped_; }

  /**
   Increment the index to the next location. Properly handles looping and buffer end.

   @param increment the increment to apply to the internal index
   @param canLoop true if looping is allowed
   */
  void increment(Float increment, bool canLoop) noexcept {
    if (finished()) return;
    state_.increment(increment, canLoop);
  }

  /// @returns index to first sample to use for rendering
  size_t whole() const noexcept { return state_.whole_; }

  /// @returns normalized position between 2 samples. For instance, 0.5 indicates half-way between two samples.
  Float partial() const noexcept { return state_.partial_; }

private:

  struct State {
    size_t whole_{0};
    Float partial_{0.0};
    Bounds bounds_{};
    bool looped_{false};

    State() = default;
    State(Bounds&& bounds) : bounds_{std::move(bounds)} {}

    void stop() noexcept { whole_ = bounds_.endPos(); }

    void increment(Float increment, bool canLoop) {
      auto wholeIncrement = size_t(increment);
      auto partialIncrement = increment - Float(wholeIncrement);

      whole_ += wholeIncrement;
      partial_ += partialIncrement;

      if (partial_ >= 1.0) {
        auto carry = size_t(partial_);
        whole_ += carry;
        partial_ -= carry;
      }

      if (canLoop && whole_ >= bounds_.endLoopPos()) {
        whole_ -= (bounds_.endLoopPos() - bounds_.startLoopPos());
        looped_ = true;
      }
      else if (whole_ >= bounds_.endPos()) {
        log_.debug() << "stopping" << std::endl;
        stop();
      }
    }
  };

  State state_{};

  inline static Logger log_{Logger::Make("Render.Sample.Generator", "Index")};
};

} // namespace Sf2::Render::Sample
