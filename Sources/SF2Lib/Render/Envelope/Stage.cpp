// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Envelope/Stage.hpp"

using namespace SF2;
using namespace SF2::Render::Envelope;

void
Stage::setConstant(int durationInSamples) noexcept
{
  durationInSamples_ = std::max(durationInSamples, 0);
  increment_ = 0_F;
}

void
Stage::setAttack(int durationInSamples) noexcept
{
  durationInSamples_ = std::max(durationInSamples, 1);
  increment_ = 1_F / durationInSamples_;
}

void
Stage::setDecay(Float sustainLevel, int durationInSamples) noexcept
{
  durationInSamples_ = std::max(durationInSamples, 1);
  if (durationInSamples_ == 1) {
    increment_ = sustainLevel - 1_F;
    return;
  }

  /*
   According to the spec, the duration for the decay stage is the amount of time that it takes to go from 1.0 to
   100 dB attenuation: "If the sustain level were -100dB, the Volume Envelope Decay Time would be the time spent in
   decay phase." This implies that the slope of the decay is based only on the duration, not on the sustain level.

   - First calculate the slope for a 1.0 - 0.0 descent over the given duration in samples
   - Calculate the actual duration to go from 1.0 to the sustain level
   - Recalculate the increment so that we reach the sustain level after the duration samples counts have passed.
   */
  auto span = (1_F - sustainLevel);
  if (span == 0_F) {
    increment_ = 0_F;
    return;
  }

  auto increment = -1_F / durationInSamples_;
  durationInSamples_ = std::max(static_cast<int>(floor(span / -increment)), 1);
  increment_ = (1_F - sustainLevel) / -durationInSamples_;
}

void
Stage::setRelease(int durationInSamples) noexcept
{
  durationInSamples_ = std::max(durationInSamples, 1);
  increment_ = -1_F / durationInSamples_;
}
