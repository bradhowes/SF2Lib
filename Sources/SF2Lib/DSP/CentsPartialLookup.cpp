// Copyright © 2022 Brad Howes. All rights reserved.

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace DSPHeaders;
using namespace SF2;
using namespace SF2::DSP;

/**
 Convert cents [0-1200) into frequency multiplier. This is used by the centsToFrequency() function to perform a fast
 conversion between cents and frequency.
 */
static constexpr int MaxCentsValue = 1200;
static constexpr size_t TableSize = MaxCentsValue;

static constexpr Float generator(size_t index) {
  return 6.875 * ConstMath::exp(index / 1200.0 * ConstMath::Constants<Float>::ln2);
}

static constexpr auto lookup_ = ConstMath::make_array<Float, TableSize>(generator);

/**
 Convert a value between 0 and 1200 into a frequency multiplier. See DSP::centsToFrequency for details on how it is
 used.

 @param partial a value between 0 and MaxCentsValue - 1
 @returns frequency multiplier
 */
Float
SF2::DSP::centsPartialLookup(int partial) noexcept {
  return lookup_[static_cast<size_t>(std::clamp(partial, 0, MaxCentsValue - 1))];
}
