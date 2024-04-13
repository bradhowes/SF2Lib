// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Voice/Sample/Generator.hpp"

using namespace SF2::Render::Voice::Sample;

void
Generator::configure(const NormalizedSampleSource& sampleSource, const State& state) noexcept
{
  bounds_ = Bounds::make(sampleSource.header(), state);
  index_.configure(bounds_);
  sampleSource_ = &sampleSource;
}
