// Copyright © 2022 Brad Howes. All rights reserved.

#include <array>
#include <cstdint>

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace DSPHeaders;
using namespace SF2;
using namespace SF2::DSP;

/**
 Lookup table for SF2 pan values, where -500 means only left-channel, and +500 means only right channel. Other values
 give attenuation values for the left and right channels between 0.0 and 1.0. These values come from the sine function
 for a pleasing audio experience when panning.

 NOTE: FluidSynth has a table size of 1002 for some reason. Thus its values are slightly off from what this table
 contains. I don't see a reason for the one extra element.
 */
static constexpr size_t TableSize = 500 + 500 + 1;

static constexpr Float Scaling = ConstMath::Constants<Float>::HalfPI / (TableSize - 1);

static constexpr Float generator(size_t index) { return ConstMath::sin(index * Scaling); }

static constexpr auto lookup_ = ConstMath::make_array<Float, TableSize>(generator);

void
SF2::DSP::panLookup(Float pan, Float& left, Float& right) noexcept {
  int index = std::clamp(static_cast<int>(std::round(pan)), -500, 500);
  left = Float(lookup_[static_cast<size_t>(-index + 500)]);
  right = Float(lookup_[static_cast<size_t>(index + 500)]);
}
