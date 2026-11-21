// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include "DSPHeaders/Biquad.hpp"
#include "SF2Util/Types.hpp"

namespace SF2::Render {

/**
 Second-order resonant low-pass filter for a voice (SF2.01 8.1.2 #8 initialFilterFc, #9 initialFilterQ).

 Coefficients are not recalculated on every sample. A voice asks `needsUpdate()` once per sample and, when it returns
 true, supplies the current cutoff and resonance via `update`. New coefficients are ramped in over `updateInterval`
 samples so that LFO and envelope sweeps of the cutoff do not produce zipper noise.
 */
class LowPassFilter
{
public:
  using Coefficients = DSPHeaders::Biquad::Coefficients<Float>;

  inline static Float defaultFrequency = 13500_F;
  inline static Float defaultResonance = 0_F;

  /// Number of samples between coefficient updates. New coefficients are ramped in over the same number of samples.
  static constexpr size_t updateInterval = 32;

  /// Cutoff in absolute cents (~20 kHz) at or above which a non-resonant filter is bypassed (SF2.01 8.1.2 #8).
  static constexpr Float bypassFrequency = 13'508_F;

  LowPassFilter(Float sampleRate = 0_F) noexcept;

  /**
   @returns true if `update` should be called before the next `transform`. Must be called once per sample.
   */
  bool needsUpdate() noexcept {
    if (samplesUntilUpdate_ > 0) {
      --samplesUntilUpdate_;
      return false;
    }
    samplesUntilUpdate_ = updateInterval - 1;
    return true;
  }

  /**
   Update the filter to use the given frequency and resonance settings. The first update after a `reset` takes effect
   immediately; later ones are ramped in over `updateInterval` samples.

   @param frequency cutoff frequency in absolute cents
   @param resonance resonance in centibels
   */
  void update(Float frequency, Float resonance) noexcept {
    if (rampUpdates_ && frequency == lastFrequency_ && resonance == lastResonance_) return;
    updateSettings(frequency, resonance, rampUpdates_ ? updateInterval : 0);
    rampUpdates_ = true;
  }

  /**
   Filter a sample using the current settings.

   @param sample the value to filter
   @returns the filtered value
   */
  Float transform(Float sample) noexcept {
    // Always run the filter, even when bypassed, so that its state stays current and there is no transient if the
    // cutoff later drops back below the bypass threshold.
    auto filtered{filter_.transform(sample)};
    return bypassed_ ? sample : filtered;
  }

  /// @returns true if the current settings bypass the filter.
  bool isBypassed() const noexcept { return bypassed_; }

  /// Clear the filter state. The next `update` call applies its settings without ramping.
  void reset() noexcept {
    filter_.reset();
    samplesUntilUpdate_ = 0;
    rampUpdates_ = false;
  }

  void setSampleRate(Float sampleRate) noexcept;

private:
  void updateSettings(Float frequency, Float resonance, size_t rampDuration) noexcept;

  DSPHeaders::Biquad::Direct<Float> filter_;
  Float sampleRate_;
  Float lastFrequency_;
  Float lastResonance_;
  size_t samplesUntilUpdate_{0};
  bool rampUpdates_{false};
  bool bypassed_{false};
};

} // end namespace SF2::Render
