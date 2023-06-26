// Copyright © 2022 Brad Howes. All rights reserved.

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace DSPHeaders;
using namespace SF2;
using namespace SF2::DSP;

static constexpr size_t TableSize = size_t(MaximumAttenuationCentiBels + 1);

static constexpr Float generator(size_t index) {
  // Equivalent to pow(10.0, Float(index) / -200.0)
  return ConstMath::exp(Float(index) / -200.0 * ConstMath::Constants<Float>::ln10);
}

static constexpr auto lookup_ = ConstMath::make_array<Float, TableSize>(generator);

Float
SF2::DSP::attenuationLookup(int centibels) noexcept {
  return Float(lookup_[static_cast<size_t>(std::clamp<int>(centibels, 0, TableSize - 1))]);
}
