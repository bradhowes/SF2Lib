// Copyright © 2022 Brad Howes. All rights reserved.

#include <array>
#include <cstdint>

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace DSPHeaders;
using namespace SF2;
using namespace SF2::DSP;

static constexpr auto lookup_ = ConstMath::make_array<Float, PanLookup::TableSize>(PanLookup::generator);

void
SF2::DSP::panLookup(Float pan, Float& left, Float& right) noexcept {
  int index = std::clamp(static_cast<int>(std::round(pan)), -500, 500);
  left = Float(lookup_[static_cast<size_t>(-index + 500)]);
  right = Float(lookup_[static_cast<size_t>(index + 500)]);
}
