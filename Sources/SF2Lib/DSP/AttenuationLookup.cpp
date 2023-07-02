// Copyright © 2022 Brad Howes. All rights reserved.

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace DSPHeaders;
using namespace SF2;
using namespace SF2::DSP;

Float
SF2::DSP::attenuationLookup(int centibels) noexcept {
  static constexpr auto lookup_ = ConstMath::make_array<Float, AttenuationLookup::TableSize>(AttenuationLookup::generator);
  return Float(lookup_[static_cast<size_t>(std::clamp<int>(centibels, 0, AttenuationLookup::TableSize - 1))]);
}
