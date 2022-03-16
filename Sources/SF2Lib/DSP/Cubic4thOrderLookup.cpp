// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/ConstMath.hpp"
#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"

using namespace SF2;
using namespace SF2::DSP;

static constexpr size_t TableSize = Interpolation::Cubic4thOrder::TableSize;

static constexpr double generator0(size_t index) {
  auto x = double(index) / double(TableSize);
  auto x_05 = 0.5 * x;
  auto x2 = x * x;
  auto x3 = x2 * x;
  auto x3_05 = 0.5 * x3;
  return -x3_05 +       x2 - x_05;
}

static constexpr double generator1(size_t index) {
  auto x = double(index) / double(TableSize);
  auto x2 = x * x;
  auto x3 = x2 * x;
  auto x3_15 = 1.5 * x3;
  return x3_15 - 2.5 * x2         + 1.0;
}

static constexpr double generator2(size_t index) {
  auto x = double(index) / double(TableSize);
  auto x_05 = 0.5 * x;
  auto x2 = x * x;
  auto x3 = x2 * x;
  auto x3_15 = 1.5 * x3;
  return -x3_15 + 2.0 * x2 + x_05;
}

static constexpr double generator3(size_t index) {
  auto x = double(index) / double(TableSize);
  auto x2 = x * x;
  auto x3 = x2 * x;
  auto x3_05 = 0.5 * x3;
  return x3_05 - 0.5 * x2;
}

using WeightsEntry = Interpolation::Cubic4thOrder::WeightsEntry;

static constexpr WeightsEntry generator(size_t index) {
  return WeightsEntry{generator0(index), generator1(index), generator2(index), generator3(index)};
}

static constexpr auto lookup_ = ConstMath::make_array<WeightsEntry, TableSize>(generator);

/**
 Obtain the cubic 4th order weights for given index value.

 @param index the index to return
 @returns reference to array of weights
 */
const WeightsEntry&
SF2::DSP::Interpolation::Cubic4thOrder::weights(size_t index) noexcept {
  return lookup_[index];
}
