// Copyright © 2022 Brad Howes. All rights reserved.

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace DSPHeaders;
using namespace SF2;
using namespace SF2::DSP;

Float
SF2::DSP::centsPartialLookup(int partial) noexcept {
  static constexpr auto lookup_ = ConstMath::make_array<Float, CentsPartialLookup::TableSize>(CentsPartialLookup::generator);
  return lookup_[static_cast<size_t>(std::clamp<size_t>(size_t(partial), 0, CentsPartialLookup::TableSize - 1))];
}
