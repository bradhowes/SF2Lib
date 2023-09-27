// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Render/LFO.hpp"

namespace SF2::Render {

class ModLFO : public LFO
{
public:

  struct Value {
    const Float val;
    Value(Float v) noexcept : val{v} {}
  };

  ModLFO(Float sampleRate) noexcept : LFO(sampleRate, "ModLFO") {}

  void configure(Voice::State::State& state) noexcept {
    LFO::configure(state.sampleRate(),
                   DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyModulatorLFO)),
                   DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayModulatorLFO)));
  }

  /**
   Obtain the value of the oscillator and advance it before returning.

   @returns next waveform value to use
   */
  inline Value getNextValue() noexcept { return LFO::getNextValue(); }

  /**
   Obtain the current value of the oscillator.

   @returns current waveform value
   */
  inline Value value() const noexcept { return LFO::value(); }

private:
  ModLFO(Float sampleRate, Float frequency, Float delay) : LFO(sampleRate, "ModLFO", frequency, delay) {}

  friend struct LFOTestInjector;
};

} // namespace SF2::Render
