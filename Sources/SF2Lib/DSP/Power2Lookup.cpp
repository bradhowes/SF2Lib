// Copyright © 2022 Brad Howes. All rights reserved.

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace DSPHeaders;
using namespace SF2;
using namespace SF2::DSP;

auto lookup_ = ConstMath::make_array<Float, Power2Lookup::TableSize>(Power2Lookup::generator);

Float
SF2::DSP::power2Lookup(int cents) noexcept {
  return lookup_[static_cast<size_t>(std::clamp<size_t>(size_t(cents + Power2Lookup::Offset), 0,
                                                        Power2Lookup::TableSize - 1))];
}
