// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Render/LFO.hpp"

namespace SF2::Render {

/**
 LFO for vibrato purposes in the audio rendering flow.
 */
class VibLFO : public LFO
{
public:

  // Typed boxed value to help ensure correctness in signal processing calls.
  struct Value {
    const Float val;
  };

  VibLFO(Float sampleRate) noexcept : LFO(sampleRate, "ModLFO") {}

  /**
   Configure the vibrato LFO using the state parameters.

   @param state the state parameters to use
   */
  void configure(Voice::State::State& state) noexcept {
    LFO::configure(state.sampleRate(),
                   DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyVibratoLFO)),
                   DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayVibratoLFO)));
  }

  /**
   Obtain the value of the oscillator and advance it before returning.

   @returns next waveform value to use
   */
  inline Value getNextValue() noexcept { return {LFO::getNextValue()}; }

  /**
   Obtain the current value of the oscillator.

   @returns current waveform value
   */
  inline Value value() const noexcept { return {LFO::value()}; }

private:
  VibLFO(Float sampleRate, Float frequency, Float delay) : LFO(sampleRate, "ModLFO", frequency, delay) {}

  friend struct LFOTestInjector;
};

} // namespace SF2::Render
