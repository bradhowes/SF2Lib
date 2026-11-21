// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "SF2Util/DSP.hpp"
#include "SF2Lib/Render/LowPassFilter.hpp"

using namespace SF2::Render;

LowPassFilter::LowPassFilter(Float sampleRate) noexcept
  : filter_{Coefficients()},
    sampleRate_{sampleRate},
    lastFrequency_{defaultFrequency},
    lastResonance_{defaultResonance}
{
  ;
}

void
LowPassFilter::updateSettings(Float frequency, Float resonance, size_t rampDuration) noexcept
{
  lastFrequency_ = frequency;
  lastResonance_ = resonance;

  // SF2.01 8.1.2 #8: "When the cutoff frequency exceeds 20kHz and the Q (resonance) of the filter is zero, the filter
  // does not affect the signal."
  bypassed_ = frequency >= bypassFrequency && resonance <= 0_F;

  // Bounds taken from FluidSynth, where the upper bound serves as an anti-aliasing filter, just below the
  // Nyquist frequency.
  auto frequencyHz = DSP::clamp(DSP::centsToFrequency(frequency), 5_F, 0.45_F * sampleRate_);
  auto coefficients{Coefficients::LPF2(sampleRate_, frequencyHz, DSP::centibelsToResonance(resonance))};

  // SF2.01 8.1.2 #9: "The filter gain at DC is also affected by this parameter such that the gain at DC is reduced by
  // half the specified gain." LPF2 has unity gain at DC, so scale the numerator.
  auto dcGain = DSP::centibelsToAttenuationInterpolated(DSP::clamp(resonance, 0_F, 960_F) / 2_F);
  coefficients.a0 *= dcGain;
  coefficients.a1 *= dcGain;
  coefficients.a2 *= dcGain;

  filter_.setCoefficients(coefficients, rampDuration);
}

void
LowPassFilter::setSampleRate(Float sampleRate) noexcept
{
  sampleRate_ = sampleRate;
  updateSettings(lastFrequency_, lastResonance_, 0);
}
