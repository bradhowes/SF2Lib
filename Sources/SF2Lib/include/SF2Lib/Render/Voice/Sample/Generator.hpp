// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>
#include <os/signpost.h>
#include <AudioToolbox/AudioToolbox.h>
#include <vector>

#include "SF2Util/DSP.hpp"
#include "SF2File/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "SF2Lib/Render/Voice/Sample/Index.hpp"
#include "SF2Lib/Render/Voice/Sample/Pitch.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"
#include "SF2Lib/Render/Zone/NormalizedSampleSpan.hpp"

namespace SF2::Render::Voice::Sample {

enum struct Interpolator {
  linear,
  cubic4thOrder
};

/**
 Generator of new samples from a stream of original samples, properly scaled to sound correct for the output sample
 rate and the desired output frequency. We know the original samples' sample rate and root frequency, so we can do some
 simple math to calculate a proper increment to use when iterating through the original samples, and with some proper
 interpolation we should end up with something that does not sound too harsh after submitting the new samples through a
 low-pass filter to remove any aliasing.
 */
class Generator {
public:
  using State = State::State;

  /**
   Construct new instance. NOTE: the instance is not usable for audio rendering at this point. One must call
   `configure` in order to be useable for rendering purposes.
   */
  Generator() noexcept {}

  /**
   Configure instance to use the given sample source. NOTE: this is invoked before start of rendering a note. This
   routine *must* ensure that the state is properly setup to do so, just as if it was created from scratch.

   @param samples the samples to use for rendering
   */
  void configure(std::shared_ptr<Zone::NormalizedSampleSpan>&& samples) noexcept { samples_ = samples; }

  /**
   Begin rendering samples from the generator. The sample bounds are calculated here rather than in `configure` so that
   they reflect every generator value applied to the voice before it starts, including live parameter overrides.

   @param state the state configuration for the voice
   */
  void start(const State& state) noexcept;

  /// Tell the generator that there will be no more samples generated.
  void stop() noexcept { index_.stop(); }

  /**
   Obtain an interpolated sample value at the current index.

   @param increment the increment to use to move to the next sample
   @param canLoop true if the generator is permitted to loop for more samples
   @returns new sample value
   */
  Float generate(Float increment, bool canLoop) noexcept
  {
    if (index_.finished()) { return 0_F; }
    // Only loop if the sample bounds define a usable loop. Otherwise `before()` could wrap to `endLoopPos - 1` when the
    // loop end is 0, reading before the start of the samples.
    canLoop = canLoop && bounds_.hasLoop();
    auto whole{index_.whole()};
    auto partial{index_.partial()};
    // Whether playback has already wrapped around the loop, taken before this increment can change it. Only then is the
    // sample before the loop start the one at the loop end.
    auto hasLooped = canLoop && index_.looped();
    index_.increment(increment, canLoop);
    return cubic4thOrderInterpolate(whole, partial, canLoop, hasLooped);
  }

  /// @returns true if sill generating samples
  bool isActive() const noexcept { return !index_.finished(); }

  /// @returns true if generator has looped during rendering.
  bool looped() const noexcept { return index_.looped(); }

private:
  /**
   Obtain a cubic 4th-order interpolated sample for a given index value.

   @param whole the index of the first sample to use
   @param partial the non-integral part of the index
   @param canLoop true if wrapping around in loop is allowed
   @param hasLooped true if playback has already wrapped around the loop
   @returns interpolated sample result
   */
  Float cubic4thOrderInterpolate(size_t whole, Float partial, bool canLoop, bool hasLooped) const noexcept {
    auto s0 = before(whole, canLoop, hasLooped);
    auto s1 = sample(whole, canLoop); ++whole;
    auto s2 = sample(whole, canLoop); ++whole;
    auto s3 = sample(whole, canLoop);
    return DSPHeaders::DSP::Interpolation::cubic4thOrder(partial, s0, s1, s2, s3) *
           Zone::NormalizedSampleSpan::normalizationScale;
  }

  /**
   Fetch a sample for interpolation. When looping, any index at or past the loop end maps back into the loop: cubic
   interpolation reads up to two samples ahead, so `endLoopPos + 1` must become `startLoopPos + 1` (only `endLoopPos`
   itself used to be wrapped).

   @param whole reference to index of the sample to fetch
   @param canLoop `true` if the samples can and should loop around
   */
  Float sample(size_t& whole, bool canLoop) const noexcept {
    if (canLoop && whole >= bounds_.endLoopPos()) {
      whole = bounds_.startLoopPos() + (whole - bounds_.endLoopPos()) % bounds_.loopSize();
    }
    return (*samples_)[whole];
  }

  /**
   Fetch the sample before `whole` for cubic interpolation. At the loop start, the sample before it is the one at the
   loop end, but only once playback has actually wrapped around: on the first pass it is the real preceding sample.
   (This used to wrap on the first pass too.)
   */
  Float before(size_t whole, bool canLoop, bool hasLooped) const noexcept {
    if (canLoop && hasLooped && whole == bounds_.startLoopPos()) { return (*samples_)[bounds_.endLoopPos() - 1]; }
    if (whole == 0) { return 0_F; }
    return (*samples_)[whole - 1];
  }

  Bounds bounds_{};
  Index index_{};
  std::shared_ptr<Zone::NormalizedSampleSpan> samples_{};
};

} // namespace SF2::Render::Sample
