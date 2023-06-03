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

  enum struct Kind {
    modulator = 1,
    vibrato = 2
  };

  static constexpr const char* logTag(Kind kind) {
    switch (kind) {
      case Kind::modulator: return "LFO<Mod>";
      case Kind::vibrato: return "LFO<Vib>";
      default: throw "invalid Kind";
    }
  }

  LFO(Float sampleRate, Kind kind) : sampleRate_{sampleRate}, kind_{kind}, log_{os_log_create("SF2Lib", logTag(kind))}
  {}

  LFO(Float sampleRate, Kind kind, Float frequency, Float delay)
  : sampleRate_{sampleRate}, kind_{kind}, log_{os_log_create("SF2Lib", logTag(kind))}
  {
    configure(sampleRate, frequency, delay);
  }

  /**
   Restart from a known zero state.
   */
  void reset() noexcept {
    counter_ = 0.0;
    if (increment_ < 0) increment_ = -increment_;
  }

  void configure(Voice::State::State& state) noexcept {
    switch (kind_) {
      case Kind::modulator:
        configure(state.sampleRate(),
                  state.modulated(Entity::Generator::Index::frequencyModulatorLFO),
                  state.modulated(Entity::Generator::Index::delayModulatorLFO));
        break;
      case Kind::vibrato:
        configure(state.sampleRate(),
                  state.modulated(Entity::Generator::Index::frequencyVibratoLFO),
                  state.modulated(Entity::Generator::Index::delayVibratoLFO));
        break;
      default:
        throw "unknown kind";
    }
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

  void configure(Float sampleRate, Float frequency, Float delay) {
    sampleRate_ = sampleRate;
    frequency_ = DSP::lfoCentsToFrequency(frequency);
    delaySampleCount_ = size_t(sampleRate_ * DSP::centsToSeconds(delay));
    increment_ = frequency_ / sampleRate_ * 4.0f;
  }

  Kind kind_;
  Float sampleRate_;
  Float frequency_{0.0};
  Float counter_{0.0};
  Float increment_{0.0};
  size_t delaySampleCount_{0};
  os_log_t log_;

  friend class LFOTestInjector;
};

} // namespace SF2::Render
