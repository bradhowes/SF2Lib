// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cassert>
#include <cmath>

#include "SF2Lib/Utils/OutputBufferPair.hpp"

namespace SF2::Utils {

/**
 Simple mixer that works with three sets of L+R buffer pairs:

 - dry -- the sum of the rendered samples from the active voices
 - chorusSend -- the sum of the fraction sent by the voice to the chorus effect
 - reverbSend -- the sum of the fraction sent by the voice to the reverb effect

 The actual movement of sample value is relegated to the OutputBufferPair entities.
 */
class Mixer
{
public:

  /**
   Construct new mixer

   @param dry the L+R buffers for the rendered voice samples
   @param chorusSend the L+R buffers for the fraction sent by each voice to the chorus effect
   @param reverbSend the L+R buffers for the fraction sent by each voice to the reverb effect
   */
  Mixer(const OutputBufferPair& dry, const OutputBufferPair& chorusSend, const OutputBufferPair& reverbSend) noexcept
  : dry_{dry}, chorusSend_{chorusSend}, reverbSend_{reverbSend}
  {}

  /**
   Construct new mixer.

   @param dry the L+R buffers for the rendered voice samples
   @param chorusSend the L+R buffers for the fraction sent by each voice to the chorus effect
   @param reverbSend the L+R buffers for the fraction sent by each voice to the reverb effect
   */
  Mixer(OutputBufferPair&& dry, OutputBufferPair&& chorusSend, OutputBufferPair&& reverbSend) noexcept
  : dry_{std::move(dry)}, chorusSend_{std::move(chorusSend)}, reverbSend_{std::move(reverbSend)}
  {}

  /**
   Add rendered samples from a voice.

   @param samples pointer to the first sample to add
   @param frameCount number of samples to add
   @param pan the panning to apply to samples when adding to the left and right channels
   @param chorusSend the gain to apply to samples when adding to the chorusSend L+R channels
   @param reverbSend the gain to apply to samples when adding to the reverbSend L+R channels
   */
  void add(const SF2::AUValue* samples, SF2::AUAudioFrameCount frameCount,
           SF2::AUValue pan, SF2::AUValue chorusSend, SF2::AUValue reverbSend) noexcept
  {
    Float leftGain;
    Float rightGain;
    DSP::panLookup(pan, leftGain, rightGain);

    dry_.add(samples, frameCount, leftGain, rightGain);
    chorusSend_.add(samples, frameCount, leftGain * chorusSend, rightGain * chorusSend);
    reverbSend_.add(samples, frameCount, leftGain * reverbSend, rightGain * reverbSend);
  }

  /**
   Advance all buffers by the given amount.

   @param shift the number of samples to advance over.
   */
  void shift(SF2::AUAudioFrameCount shift) noexcept {
    dry_.shift(shift);
    chorusSend_.shift(shift);
    reverbSend_.shift(shift);
  }

private:
  OutputBufferPair dry_;
  OutputBufferPair chorusSend_;
  OutputBufferPair reverbSend_;
};

} // end namespace
