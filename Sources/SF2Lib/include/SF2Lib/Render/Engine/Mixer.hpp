// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include <cassert>

#include "DSPHeaders/BusBuffers.hpp"
#include "SF2Util/Types.hpp"

namespace SF2::Render::Engine {

class Mixer
{
public:
  /**
   Construct new mixer that consists of three output busses. The arguments take a value type so that they may be
   constructed at the call site or used directly from a function return. Alternative would be to define move operations
   but `BusBuffers` just holds a (shared) reference to a vector, so copies are quick.

   @param dry the dry (original) output samples
   @param chorusSend the samples that will go to the first effects channel
   @param reverbSend the samples that will go to the second effects channel
   */
  Mixer(DSPHeaders::BusBuffers dry, DSPHeaders::BusBuffers chorusSend, DSPHeaders::BusBuffers reverbSend) noexcept :
  dry_{dry}, chorusSend_{chorusSend}, reverbSend_{reverbSend}
  {
    ;
  }

  /**
   Add a sample to the output buffers.

   @param frame the frame to hold the samples
   @param left the sample for the left channel
   @param right the sample for the right channel
   @param chorusLevel the amount of the L+R samples to send to the chorusSend bus
   @param reverbLevel the amount of the L+R samples to send to the reverbSend bus
   */
  void add(AUAudioFrameCount frame, AUValue left, AUValue right, AUValue chorusLevel, AUValue reverbLevel) noexcept
  {
    dry_.addStereo(frame, left, right);
    if (chorusSend_.isValid()) chorusSend_.addStereo(frame, left * chorusLevel, right * chorusLevel);
    if (reverbSend_.isValid()) reverbSend_.addStereo(frame, left * reverbLevel, right * reverbLevel);
  }

  /**
   Add a block of mono voice samples to the output buffers, panned and sent to the effects buses. Gives the same results
   as calling `add` for each frame with `AUValue(leftPan * sample)` and `AUValue(rightPan * sample)`, but each bus is
   updated in its own branch-free loop over contiguous memory, which the compiler can vectorize.

   @param start the frame of the first sample
   @param samples the voice samples to add
   @param count the number of samples (at most `maxBlockSize`)
   @param leftPan gain for the left channel
   @param rightPan gain for the right channel
   @param chorusLevel the amount of the L+R samples to send to the chorusSend bus
   @param reverbLevel the amount of the L+R samples to send to the reverbSend bus
   */
  void addBlock(AUAudioFrameCount start, const Float* samples, AUAudioFrameCount count, Float leftPan, Float rightPan,
                AUValue chorusLevel, AUValue reverbLevel) noexcept
  {
    assert(count <= maxBlockSize);
    AUValue left[maxBlockSize];
    AUValue right[maxBlockSize];
    for (AUAudioFrameCount index = 0; index < count; ++index) {
      left[index] = AUValue(leftPan * samples[index]);
      right[index] = AUValue(rightPan * samples[index]);
    }

    addBus(dry_, start, left, right, count);
    if (chorusSend_.isValid()) addBus(chorusSend_, start, left, right, count, chorusLevel);
    if (reverbSend_.isValid()) addBus(reverbSend_, start, left, right, count, reverbLevel);
  }

  /// Largest block that `addBlock` accepts
  static constexpr AUAudioFrameCount maxBlockSize = 64;

  /**
   Command the individual BusBuffer instances to shift forward by `frames` frames. NOTE: only used in tests.

   @param frames the number of frames to shift over
   */
  void shiftOver(AUAudioFrameCount frames) noexcept
  {
    dry_.shiftOver(frames);
    chorusSend_.shiftOver(frames);
    reverbSend_.shiftOver(frames);
  }

private:

  /// Add `left` and `right` to the two channels of `bus`. Like `BusBuffers::addStereo`, nothing is added unless both
  /// channels have buffers.
  static void addBus(const DSPHeaders::BusBuffers& bus, AUAudioFrameCount start, const AUValue* __restrict left,
                     const AUValue* __restrict right, AUAudioFrameCount count) noexcept
  {
    assert(bus.isStereo());
    AUValue* __restrict leftOut = bus[0];
    AUValue* __restrict rightOut = bus[1];
    if (leftOut == nullptr || rightOut == nullptr) [[unlikely]] return;
    leftOut += start;
    rightOut += start;
    for (AUAudioFrameCount index = 0; index < count; ++index) leftOut[index] += left[index];
    for (AUAudioFrameCount index = 0; index < count; ++index) rightOut[index] += right[index];
  }

  /// Add `left` and `right` scaled by `level` to the two channels of `bus`.
  static void addBus(const DSPHeaders::BusBuffers& bus, AUAudioFrameCount start, const AUValue* __restrict left,
                     const AUValue* __restrict right, AUAudioFrameCount count, AUValue level) noexcept
  {
    assert(bus.isStereo());
    AUValue* __restrict leftOut = bus[0];
    AUValue* __restrict rightOut = bus[1];
    if (leftOut == nullptr || rightOut == nullptr) [[unlikely]] return;
    leftOut += start;
    rightOut += start;
    // The product is a separate statement so that it is not fused with the addition: `add` multiplies and adds in
    // separate expressions, and the results must match it exactly.
    for (AUAudioFrameCount index = 0; index < count; ++index) {
      AUValue value = left[index] * level;
      leftOut[index] += value;
    }
    for (AUAudioFrameCount index = 0; index < count; ++index) {
      AUValue value = right[index] * level;
      rightOut[index] += value;
    }
  }

  DSPHeaders::BusBuffers dry_;
  DSPHeaders::BusBuffers chorusSend_;
  DSPHeaders::BusBuffers reverbSend_;
};

} // end namespace
