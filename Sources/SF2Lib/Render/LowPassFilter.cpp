// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Render/LFO.hpp"

using namespace SF2::Render;

LFO::LFO(Float sampleRate, const char* logTag) noexcept :
log_{os_log_create("SF2Lib", logTag)}
{
  configure(sampleRate, 0.0, -12'000.0);
}

LFO::LFO(Float sampleRate, const char* logTag, Float frequency, Float delay) :
log_{os_log_create("SF2Lib", logTag)}
{
  configure(sampleRate, frequency, delay);
}

void
LFO::configure(Float sampleRate, Float frequency, Float delay)
{
  delaySampleCount_ = static_cast<size_t>(sampleRate * delay);
  increment_ = frequency / sampleRate * Float(4.0);
}
