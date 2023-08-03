// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>
#include <os/signpost.h>
#include <AudioToolbox/AudioToolbox.h>
#include <vector>

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/NormalizedSampleSource.hpp"
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "SF2Lib/Render/Voice/Sample/Index.hpp"
#include "SF2Lib/Render/Voice/Sample/Pitch.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render::Voice::Sample {

/**
 Generator of new samples from a stream of original samples, properly scaled to sound correct for the output sample
 rate and the desired output frequency. We know the original samples' sample rate and root frequency, so we can do some
 simple math to calculate a proper increment to use when iterating through the original samples, and with some proper
 interpolation we should end up with something that does not sound too harsh.
 */
class Generator {
public:
  using State = State::State;

  enum struct Interpolator {
    linear,
    cubic4thOrder
  };

  /**
   Construct new instance. NOTE: the instance is not usable for audio rendering at this point. One must call
   `configure` in order to be useable for rendering purposes.

   @param kind the interpolation to apply to the samples
   */
  Generator(Interpolator kind) noexcept : interpolatorProc_{interpolator(kind)} {}

  /**
   Configure instance to use the given sample source. NOTE: this is invoked before start of rendering a note. This
   routine *must* ensure that the state is properly setup to do so, just as if it was created from scratch.

   @param sampleSource the samples to use for rendering
   @param state the state configuration for the voice
   */
  void configure(const NormalizedSampleSource& sampleSource, const State& state) noexcept
  {
    bounds_ = Bounds::make(sampleSource.header(), state);
    index_.configure(bounds_);
    sampleSource_ = &sampleSource;
    sampleSource_->load();
  }

  /**
   Obtain an interpolated sample value at the current index.

   @param increment the increment to use to move to the next sample
   @param canLoop true if the generator is permitted to loop for more samples
   @returns new sample value
   */
  Float generate(Float increment, bool canLoop) noexcept
  {
    if (index_.finished()) return 0.0;
    auto whole = index_.whole();
    auto partial = index_.partial();
    index_.increment(increment, canLoop);
    return (this->*interpolatorProc_)(whole, partial, canLoop);
  }

  /// @returns true if sill generating samples
  bool isActive() const noexcept { return !index_.finished(); }

  /// @returns true if generator has looped during rendering.
  bool looped() const noexcept { return index_.looped(); }

  /// Tell the generator that there will be no more samples generated.
  void stop() noexcept { index_.stop(); }

private:
  using InterpolatorProc = Float (Generator::*)(size_t, Float, bool) const;

  static InterpolatorProc interpolator(Interpolator kind) noexcept {
    return kind == Interpolator::linear ? &Generator::linearInterpolate : &Generator::cubic4thOrderInterpolate;
  }

  /**
   Obtain a linearly interpolated sample for a given index value.

   @param whole the index of the first sample to use
   @param partial the non-integral part of the index
   @param canLoop true if wrapping around in loop is allowed
   @returns interpolated sample result
   */
  Float linearInterpolate(size_t whole, Float partial, bool canLoop) const noexcept {
    return Float(DSPHeaders::DSP::Interpolation::linear(partial, sample(whole, canLoop), sample(whole + 1, canLoop)));
  }

  /**
   Obtain a cubic 4th-order interpolated sample for a given index value.

   @param whole the index of the first sample to use
   @param partial the non-integral part of the index
   @param canLoop true if wrapping around in loop is allowed
   @returns interpolated sample result
   */
  Float cubic4thOrderInterpolate(size_t whole, Float partial, bool canLoop) const noexcept {
    return Float(DSPHeaders::DSP::Interpolation::cubic4thOrder(partial, before(whole, canLoop), sample(whole, canLoop),
                                                               sample(whole + 1, canLoop), sample(whole + 2, canLoop)));
  }

  Float sample(size_t whole, bool canLoop) const noexcept {
    if (whole == bounds_.endLoopPos() && canLoop) whole = bounds_.startLoopPos();
    return whole < sampleSource_->size() ? (*sampleSource_)[whole] : 0.0;
  }

  Float before(size_t whole, bool canLoop) const noexcept {
    if (whole == 0) return 0.0;
    if (whole == bounds_.startLoopPos() && canLoop) whole = bounds_.endLoopPos();
    return (*sampleSource_)[whole - 1];
  }

  Bounds bounds_;
  Index index_;
  const InterpolatorProc interpolatorProc_;
  const NormalizedSampleSource* sampleSource_{nullptr};
};

} // namespace SF2::Render::Sample
