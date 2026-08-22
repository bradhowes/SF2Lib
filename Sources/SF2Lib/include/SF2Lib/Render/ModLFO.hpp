// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Render/LFO.hpp"

namespace SF2::Render {

/**
 LFO for modulating purposes in the audio rendering flow.
 */
class ModLFO : public LFO
{
public:
  // Typed boxed value to help ensure correctness in signal processing calls.
  struct Value {
    const Float val;
  };

  ModLFO() noexcept : LFO("ModLFO") {}

  /**
   Configure the modulating LFO using the state parameters.

   @param state the state parameters to use
   */
  inline void configure(Voice::State::State& state) noexcept {
    LFO::configure(state.sampleRate(),
                   DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyModulatorLFO)),
                   DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayModulatorLFO)));
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
  ModLFO(Float sampleRate, Float frequency, Float delay) : LFO(sampleRate, "ModLFO", frequency, delay) {}

  friend struct LFOTestInjector;
};

} // namespace SF2::Render
