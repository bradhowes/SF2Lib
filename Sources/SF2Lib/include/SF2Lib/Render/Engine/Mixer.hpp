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
   but `BufferPair` just holds two AUValue pointers so there is no cost to doing a copy.

   @param dry the dry (original) output samples
   @param chorusSend the samples that will go to the first effects channel
   @param reverbSend the samples that will go to the second effects channel
   */
  Mixer(DSPHeaders::BusBuffers dry, DSPHeaders::BusBuffers effects1, DSPHeaders::BusBuffers effects2) :
  dry_{dry}, effects1_{effects1}, effects2_{effects2}
  {
    ;
  }

  /**
   Add a sample to the output buffers.

   @param frame the frame to hold the samples
   @param left the sample for the left channel
   @param right the sample for the right channel
   @param effect1 the amount of the L+R samples to send to the first effects bus
   @param effect2 the amount of the L+R samples to send to the second effects bus
   */
  void add(AUAudioFrameCount frame, AUValue left, AUValue right, AUValue effects1, AUValue effects2) noexcept
  {
    dry_.addStereo(frame, left, right);
    if (effects1_.isValid() && effects1 > 0.0) effects1_.addStereo(frame, left * effects1, right * effects1);
    if (effects2_.isValid() && effects2 > 0.0) effects2_.addStereo(frame, left * effects2, right * effects2);
  }

  /**
   Command the individual BufferPair instances to shift forward by `frames` frames.

   @param frames the number of frames to shift over
   */
  void shiftOver(AUAudioFrameCount frames)
  {
    dry_.shiftOver(frames);
    effects1_.shiftOver(frames);
    effects2_.shiftOver(frames);
  }

private:
  DSPHeaders::BusBuffers dry_;
  DSPHeaders::BusBuffers effects1_;
  DSPHeaders::BusBuffers effects2_;
};

} // end namespace