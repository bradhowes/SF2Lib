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
   @param chorus the amount of the L+R samples to send to the chorusSend bus
   @param reverb the amount of the L+R samples to send to the reverbSend bus
   */
  void add(AUAudioFrameCount frame, AUValue left, AUValue right, AUValue chorus, AUValue reverb) noexcept
  {
    dry_.addStereo(frame, left, right);
    if (chorusSend_.isValid() && chorus > 0.0) chorusSend_.addStereo(frame, left * chorus, right * chorus);
    if (reverbSend_.isValid() && reverb > 0.0) reverbSend_.addStereo(frame, left * reverb, right * reverb);
  }

  /**
   Command the individual BufferPair instances to shift forward by `frames` frames.

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
