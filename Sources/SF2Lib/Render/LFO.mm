// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Util/DSP.hpp"
#include "SF2Lib/Render/LFO.hpp"

using namespace SF2::Render;

void
LFO::configure(Float sampleRate, Float frequency, Float delay)
{
  delaySampleCount_ = static_cast<size_t>(sampleRate * delay);
  increment_ = frequency / sampleRate * 4_F;
}
