// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Render/LowPassFilter.hpp"

using namespace SF2::Render;

LowPassFilter::LowPassFilter(Float sampleRate) noexcept :
filter_{Coefficients()},
sampleRate_{sampleRate},
lastFrequency_{defaultFrequency},
lastResonance_{defaultResonance}
{
  updateSettings(defaultFrequency, defaultResonance);
}

void
LowPassFilter::updateSettings(Float frequency, Float resonance) noexcept
{
  lastFrequency_ = frequency;
  lastResonance_ = resonance;

  // Bounds taken from FluidSynth, where the upper bound serves as an anti-aliasing filter, just below the
  // Nyquist frequency.
  frequency = DSP::clamp(DSP::centsToFrequency(frequency), 5.0f, 0.45f * sampleRate_);
  resonance = DSP::centibelsToResonance(resonance);
  filter_.setCoefficients(Coefficients::LPF2(sampleRate_, frequency, resonance));
}

void
LowPassFilter::setSampleRate(Float sampleRate) noexcept
{
  sampleRate_ = sampleRate;
  updateSettings(lastFrequency_, lastResonance_);
}
