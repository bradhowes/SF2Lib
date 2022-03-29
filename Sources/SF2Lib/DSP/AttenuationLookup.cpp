// Copyright © 2022 Brad Howes. All rights reserved.

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace DSPHeaders;
using namespace SF2;
using namespace SF2::DSP;

static constexpr size_t TableSize = 1441;

static constexpr double generator(size_t index) {
  return ConstMath::exp(double(index) / -200.0 * ConstMath::Constants<double>::ln10);
}

static constexpr auto lookup_ = ConstMath::make_array<double, TableSize>(generator);

/**
 Convert a value between 0 and 1440 into an attenuation.

 @param centibels a value between 0 and 1440
 @returns attenuation
 */
Float
SF2::DSP::attenuationLookup(int centibels) noexcept {
  return Float(lookup_[static_cast<size_t>(std::clamp<int>(centibels, 0, TableSize - 1))]);
}
