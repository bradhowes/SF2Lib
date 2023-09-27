// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Render/LFO.hpp"

namespace SF2::Render {

class VibLFO : public LFO
{
public:

  struct Value {
    const Float val;
    Value(Float v) noexcept : val{v} {}
  };

  VibLFO(Float sampleRate) noexcept : LFO(sampleRate, "ModLFO") {}

  void configure(Voice::State::State& state) noexcept {
    LFO::configure(state.sampleRate(),
                   DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyVibratoLFO)),
                   DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayVibratoLFO)));
  }

  /**
   Obtain the value of the oscillator and advance it before returning.

   @returns next waveform value to use
   */
  Value getNextValue() noexcept { return LFO::getNextValue(); }

  /**
   Obtain the current value of the oscillator.

   @returns current waveform value
   */
  Value value() const noexcept { return LFO::value(); }

private:
  VibLFO(Float sampleRate, Float frequency, Float delay) : LFO(sampleRate, "ModLFO", frequency, delay) {}

  friend struct LFOTestInjector;
};

} // namespace SF2::Render
