// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include "DSPHeaders/Biquad.hpp"
#include "SF2Util/Types.hpp"

namespace SF2::Render {

class LowPassFilter
{
public:
  using Coefficients = DSPHeaders::Biquad::Coefficients<Float>;

  inline static Float defaultFrequency = 13500_F;
  inline static Float defaultResonance = 0_F;

  LowPassFilter(Float sampleRate = 0_F) noexcept;

  /**
   Update the filter to use the given frequency and resonance settings.

   @param frequency frequency represented in cents
   @param resonance resonance in centiBels
   */
  inline Float transform(Float frequency, Float resonance, Float sample) noexcept {
    return sample;
    if (lastFrequency_ != frequency || lastResonance_ != resonance) updateSettings(frequency, resonance);
    return filter_.transform(sample);
  }

  void reset() noexcept { filter_.reset(); }

  void setSampleRate(Float sampleRate) noexcept;

private:
  void updateSettings(Float frequency, Float resonance) noexcept;

  DSPHeaders::Biquad::Direct<Float> filter_;
  Float sampleRate_;
  Float lastFrequency_;
  Float lastResonance_;
};

} // end namespace SF2::Render
