// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cmath>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render {

/**
 There are two kinds of LFOs in the SF2 universe:
 - modulator -- affects the modulation of the signal
 - vibrato -- provides a slight pitch change of a note
 */
enum struct LFOKind {
  modulator = 1,
  vibrato = 2
};

/**
 Implementation of a low-frequency triangular oscillator.

 By design, this LFO emits bipolar values from -1.0 to 1.0 in
 order to be useful in SF2 processing. One can obtain unipolar values via the DSP::bipolarToUnipolar method.
 An LFO can be configured to delay oscillating for N samples. During that time it will emit 0.0. After the optional
 delay setting, the LFO will start emitting the positive edge ascending edge of the waveform, starting at 0.0, in order
 to smoothly transition from a paused LFO into a running one. This is by design and per SF2 spec.

 The `Kind` template argument defines which kind of LFO that is being used, general-purpose modulation or vibrato.
 */
template <enum struct LFOKind Kind>
class LFO {
public:

  /**
   Custom type for values from this LFO. Each LFO "kind" has its own value type in order to catch mistakes wiring with
   the wrong one.
   */
  struct Value {
    Float val;
    explicit Value(Float v) noexcept : val{v} {}
  };

  /// Obtain a log tag to use based on the LFOKind enum value.
  static constexpr const char* logTag(LFOKind kind) {
    switch (kind) {
      case LFOKind::modulator: return "LFO<Mod>";
      case LFOKind::vibrato: return "LFO<Vib>";
      default: throw "invalid Kind";
    }
  }

  /**
   Construct new LFO. It will have no frequency so it will never return a non-zero value.

   @param sampleRate the sample rate being used
   */
  LFO(Float sampleRate) : log_{os_log_create("SF2Lib", logTag(Kind))}
  {
    configure(sampleRate, 0.0, -12'000.0);
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
    switch (Kind) {
      case LFOKind::modulator:
        configure(state.sampleRate(),
                  DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyModulatorLFO)),
                  DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayModulatorLFO)));
        break;

      case LFOKind::vibrato:
        configure(state.sampleRate(),
                  DSP::lfoCentsToFrequency(state.modulated(Entity::Generator::Index::frequencyVibratoLFO)),
                  DSP::centsToSeconds(state.modulated(Entity::Generator::Index::delayVibratoLFO)));
        break;

      default:
        throw "unknown kind";
    }
  }

  /**
   Advance the current value of the LFO to the next value. NOTE: this is automatically done by `getNextValue` method.
   */
  void increment() noexcept {
    if (delaySampleCount_ > 0) {
      --delaySampleCount_;
      return;
    }

    counter_ += increment_;
    if (counter_ >= 1.0) {
      increment_ = -increment_;
      counter_ = 2.0f - counter_;
    }
    else if (counter_ <= -1.0) {
      increment_ = -increment_;
      counter_ = -2.0f - counter_;
    }
  }

  /**
   Obtain the value of the oscillator and advance it before returning.

   @returns next waveform value to use
   */
  Value getNextValue() noexcept {
    auto counter = counter_;
    increment();
    return Value(counter);
  }

  /**
   Obtain the current value of the oscillator.

   @returns current waveform value
   */
  Value value() const noexcept { return Value(counter_); }

private:

  /**
   Construct new LFO. NOTE: this is only used in tests.

   @param sampleRate the sample rate being used
   @param frequency the frequency of the LFO in cycles per second (Hz)
   @param delay the number of seconds to delay the start of the LFO
   */
  LFO(Float sampleRate, Float frequency, Float delay) : log_{os_log_create("SF2Lib", logTag(Kind))}
  {
    configure(sampleRate, frequency, delay);
  }

  void configure(Float sampleRate, Float frequency, Float delay) {
    delaySampleCount_ = size_t(sampleRate * delay);
    increment_ = frequency / sampleRate * 4.0f;
  }

  Float counter_{0.0};
  Float increment_{0.0};
  size_t delaySampleCount_{0};

  const os_log_t log_;

  template<enum struct LFOKind> friend struct LFOTestInjector;
};

using ModLFO = LFO<LFOKind::modulator>;
using VibLFO = LFO<LFOKind::vibrato>;

} // namespace SF2::Render
