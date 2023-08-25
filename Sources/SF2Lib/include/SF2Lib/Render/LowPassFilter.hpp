// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cassert>
#include <iostream>

#include "SF2Lib/DSP.hpp"
#include "DSPHeaders/Biquad.hpp"

namespace SF2::Render {

class LowPassFilter
{
public:
  using Coefficients = DSPHeaders::Biquad::Coefficients<Float>;

  inline static Float defaultFrequency = 13500;
  inline static Float defaultResonance = 0.0;

  LowPassFilter(Float sampleRate) noexcept;

  /**
   Update the filter to use the given frequency and resonance settings.

   @param frequency frequency represented in cents
   @param resonance resonance in centiBels
   */
  Float transform(Float frequency, Float resonance, Float sample) noexcept {
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
