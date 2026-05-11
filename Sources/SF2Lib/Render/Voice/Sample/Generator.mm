// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Voice/Sample/Generator.hpp"

using namespace SF2::Render::Voice::Sample;

void
Generator::configure(std::shared_ptr<Zone::NormalizedSampleSpan>&& samples, const State& state) noexcept
{
  samples_ = samples;
  bounds_ = Bounds::make(samples_->header(), state);
  index_.configure(bounds_);
}
