// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cmath>

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render {

/**
 Implementation of a low-frequency triangular oscillator.

 By design, this LFO emits bipolar values from -1.0 to 1.0 in
 order to be useful in SF2 processing. One can obtain unipolar values via the DSP::bipolarToUnipolar method.
 An LFO can be configured to delay oscillating for N samples. During that time it will emit 0.0. After the optional
 delay setting, the LFO will start emitting the positive edge ascending edge of the waveform, starting at 0.0, in order
 to smoothly transition from a paused LFO into a running one. This is by design and per SF2 spec.
 */
class LFO {
public:

  /**
   Restart from a known zero state.
   */
  void reset() noexcept {
    counter_ = 0.0;
    if (increment_ < 0) increment_ = -increment_;
  }

protected:

  /**
   Construct new LFO. It will have no frequency so it will never return a non-zero value.

   @param sampleRate the sample rate being used
   */
  LFO(Float sampleRate, const char* logTag) noexcept;

  /**
   Construct new LFO. NOTE: this is only used in tests.

   @param sampleRate the sample rate being used
   @param frequency the frequency of the LFO in cycles per second (Hz)
   @param delay the number of seconds to delay the start of the LFO
   */
  LFO(Float sampleRate, const char* logTag, Float frequency, Float delay);

  /**
   Advance the current value of the LFO to the next value. NOTE: this is automatically done by `getNextValue` method.
   */
  void increment() noexcept {
    if (delaySampleCount_ > 0) {
      --delaySampleCount_;
      return;
    }

    counter_ += increment_;
    if (counter_ >= 1.0_F) {
      increment_ = -increment_;
      counter_ = 2.0_F - counter_;
    }
    else if (counter_ <= -1.0_F) {
      increment_ = -increment_;
      counter_ = -2.0_F - counter_;
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

  void configure(Float sampleRate, Float frequency, Float delay);

  Float counter_{0.0_F};
  Float increment_{0.0_F};
  size_t delaySampleCount_{0};

  const os_log_t log_;
};

} // namespace SF2::Render
