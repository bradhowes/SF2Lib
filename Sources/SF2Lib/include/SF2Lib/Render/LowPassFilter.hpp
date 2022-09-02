// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cassert>
#include <iostream>

#include "SF2Lib/DSP/DSP.hpp"
#include "DSPHeaders/Biquad.hpp"

namespace SF2::Render {

class LowPassFilter
{
public:
  using Coefficients = DSPHeaders::Biquad::Coefficients<Float>;

  inline static Float defaultFrequency = 13500;
  inline static Float defaultResonance = 0.0;

  LowPassFilter(Float sampleRate) noexcept :
  filter_{Coefficients()}, sampleRate_{sampleRate},
  lastFrequency_{defaultFrequency}, lastResonance_{defaultResonance}
  {
    updateSettings(defaultFrequency, defaultResonance);
  }

  /**
   Update the filter to use the given frequency and resonance settings.

   @param frequency frequency represented in cents
   @param resonance resonance in centiBels
   */
  Float transform(Float frequency, Float resonance, Float sample) noexcept {
    // return sample;
    
    if (lastFrequency_ != frequency || lastResonance_ != resonance) {
      updateSettings(frequency, resonance);

      // Bounds taken from FluidSynth, where the upper bound serves as an anti-aliasing filter, just below the
      // Nyquist frequency.
      frequency = std::clamp(DSP::centsToFrequency(frequency), 5.0, 0.45 * sampleRate_);
      resonance = DSP::centibelsToResonance(resonance);
      filter_.setCoefficients(Coefficients::LPF2(sampleRate_, frequency, resonance));
    }

    return filter_.transform(sample);
  }

  void reset() noexcept { filter_.reset(); }

private:

  void updateSettings(Float frequency, Float resonance) noexcept
  {
    lastFrequency_ = frequency;
    lastResonance_ = resonance;

    // Bounds taken from FluidSynth, where the upper bound serves as an anti-aliasing filter, just below the
    // Nyquist frequency.
    frequency = std::clamp(DSP::centsToFrequency(frequency), 5.0, 0.45 * sampleRate_);
    resonance = DSP::centibelsToResonance(resonance);
    filter_.setCoefficients(Coefficients::LPF2(sampleRate_, frequency, resonance));
  }

  DSPHeaders::Biquad::Direct<Float> filter_;
  Float sampleRate_;
  Float lastFrequency_;
  Float lastResonance_;
};

} // end namespace SF2::Render
