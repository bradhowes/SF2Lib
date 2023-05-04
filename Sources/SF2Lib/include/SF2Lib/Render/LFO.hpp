// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cmath>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render {

/**
 Implementation of a low-frequency triangular oscillator. By design, this LFO emits bipolar values from -1.0 to 1.0 in
 order to be useful in SF2 processing. One can obtain unipolar values via the DSP::bipolarToUnipolar method. An LFO
 will start emitting with value 0.0, again by design, in order to smoothly transition from a paused LFO into a running
 one. An LFO can be configured to delay oscillating for N samples. During that time it will emit 0.0.
 */
class LFO {
public:

  static LFO forModulator(Voice::State::State& state) noexcept {
    return LFO(state.sampleRate(),
               DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyModulatorLFO)),
               DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayModulatorLFO)));
  }

  static LFO forVibrato(Voice::State::State& state) noexcept {
    return LFO(state.sampleRate(),
               DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyVibratoLFO)),
               DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayVibratoLFO)));
  }

  LFO() = default;

  /**
   Restart from a known zero state.
   */
  void reset() noexcept {
    counter_ = 0.0;
    if (increment_ < 0) increment_ = -increment_;
  }

  /**
   Obtain the value of the oscillator and advance it before returning.

   @returns next waveform value to use
   */
  Float getNextValue() noexcept {
    auto counter = counter_;
    increment();
    return counter;
  }

  /**
   Obtain the current value of the oscillator.

   @returns current waveform value
   */
  constexpr Float value() const noexcept { return counter_; }

  void increment() noexcept {
    if (delaySampleCount_ > 0) [[unlikely]] {
      --delaySampleCount_;
      return;
    }

    counter_ += increment_;
    if (counter_ >= 1.0) [[unlikely]] {
      increment_ = -increment_;
      counter_ = 2.0f - counter_;
    }
    else if (counter_ <= -1.0) [[unlikely]] {
      increment_ = -increment_;
      counter_ = -2.0f - counter_;
    }
  }

private:

  /**
   Create a new instance.
   */
  LFO(Float sampleRate, Float frequency, Float delay) noexcept :
  sampleRate_{sampleRate}, frequency_{frequency}, delaySampleCount_{size_t(sampleRate_ * delay)},
  increment_{frequency / sampleRate * 4.0f} {}

  friend class LFOTestInjector;
  
  Float sampleRate_;
  Float frequency_;
  Float counter_{0.0};
  Float increment_;
  size_t delaySampleCount_;
};

} // namespace SF2::Render
