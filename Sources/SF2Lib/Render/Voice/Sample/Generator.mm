// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Voice/Sample/Generator.hpp"

using namespace SF2::Render::Voice::Sample;

void
Generator::start(const State& state) noexcept
{
  bounds_ = Bounds::make(samples_->header(), state);
  index_.configure(bounds_);
  index_.start();
}
