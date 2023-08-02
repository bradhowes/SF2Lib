// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cassert>
#include <cmath>
#include <vector>

#include "DSPHeaders/BusBuffers.hpp"

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

  Mixer() = delete;

  Mixer(const Mixer& other) = default;

  Mixer(Mixer&& other) = default;

  Mixer& operator =(Mixer&&) = delete;

  Mixer& operator =(const Mixer&) = delete;

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
   Command the individual BusBuffer instances to shift forward by `frames` frames.

   @param frames the number of frames to shift over
   */
  void shiftOver(AUAudioFrameCount frames) noexcept
  {
    dry_.shiftOver(frames);
    chorusSend_.shiftOver(frames);
    reverbSend_.shiftOver(frames);
  }

private:
  DSPHeaders::BusBuffers dry_;
  DSPHeaders::BusBuffers chorusSend_;
  DSPHeaders::BusBuffers reverbSend_;
};

} // end namespace
