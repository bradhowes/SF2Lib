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

  /**
   There are two kinds of LFOs in the SF2 universe:
   - modulator -- affects the modulation of the signal
   - vibrato -- provides a slight pitch change of a note
   */
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

  /**
   Construct new LFO. It will have no frequency so it will never return a non-zero value.

   @param sampleRate the sample rate being used
   @param kind the kind of LFO
   */
  LFO(Float sampleRate, Kind kind) : kind_{kind}, log_{os_log_create("SF2Lib", logTag(kind))}
  {
    configure(sampleRate, 0.0, -12'000.0);
  }

  /**
   Construct new LFO.

   @param sampleRate the sample rate being used
   @param kind the kind of LFO
   @param frequency the frequency of the LFO in cycles per second (Hz)
   @param delay the number of seconds to delay the start of the LFO
   */
  LFO(Float sampleRate, Kind kind, Float frequency, Float delay)
  : kind_{kind}, log_{os_log_create("SF2Lib", logTag(kind))}
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

  /**
   Configure the LFO using values from a voice State.

   @param state the collection of SF2 generators to use for the frequency and delay parameters.
   */
  void configure(Voice::State::State& state) noexcept {
    switch (kind_) {
      case Kind::modulator:
        configure(state.sampleRate(),
                  DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyModulatorLFO)),
                  DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayModulatorLFO)));
        break;

      case Kind::vibrato:
        configure(state.sampleRate(),
                  DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyVibratoLFO)),
                  DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayVibratoLFO)));
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
    delaySampleCount_ = size_t(sampleRate * delay);
    increment_ = frequency / sampleRate * 4.0f;
  }

  Kind kind_;
  Float counter_{0.0};
  Float increment_{0.0};
  size_t delaySampleCount_{0};
  os_log_t log_;

  friend class LFOTestInjector;
};

} // namespace SF2::Render
