// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <functional>

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

using namespace SF2;
using namespace SF2::MIDI;
using namespace DSPHeaders::ConstMath;

constexpr Float positiveLinear(size_t maxValue, size_t index) noexcept {
  return Float(index) / Float(maxValue + 1);
}

constexpr Float positiveConcave(size_t maxValue, size_t index) noexcept {
  return index == maxValue ? 1.0 : -40.0 / 96.0 * log10((maxValue - index) / Float(maxValue));
}

constexpr Float positiveConvex(size_t maxValue, size_t index) noexcept {
  return index == 0 ? 0.0 : 1.0 - -40.0 / 96.0 * log10(index / Float(maxValue));
}

constexpr Float positiveSwitched(size_t maxValue, size_t index) noexcept {
  return index <= maxValue / 2 ? 0.0 : 1.0;
}

constexpr Float negativeLinear(size_t maxValue, size_t index) noexcept {
  return 1.0f - positiveLinear(maxValue, index);
}

constexpr Float negativeConcave(size_t maxValue, size_t index) noexcept {
  return index == 0 ? 1.0 : -40.0 / 96.0 * log10(index / Float(maxValue));
}

constexpr Float negativeConvex(size_t maxValue, size_t index) noexcept {
  return index == maxValue ? 0.0 : 1.0 - -40.0 / 96.0 * log10((maxValue - index) / Float(maxValue));
}

constexpr Float negativeSwitched(size_t maxValue, size_t index) noexcept {
  return 1.0f - positiveSwitched(maxValue, index);
}

using Generator = Float(*)(size_t, size_t);

Generator proc(ValueTransformer::Kind kind, ValueTransformer::Direction dir) noexcept {
  switch (kind) {
    case ValueTransformer::Kind::linear:
      return dir == ValueTransformer::Direction::ascending ? positiveLinear : negativeLinear;
    case ValueTransformer::Kind::concave:
      return dir == ValueTransformer::Direction::ascending ? positiveConcave : negativeConcave;
    case ValueTransformer::Kind::convex:
      return dir == ValueTransformer::Direction::ascending ? positiveConvex : negativeConvex;
    case ValueTransformer::Kind::switched:
      return dir == ValueTransformer::Direction::ascending ? positiveSwitched : negativeSwitched;
  }
}

size_t transformArrayIndex(size_t maxValue, ValueTransformer::Kind kind, ValueTransformer::Direction dir,
                           ValueTransformer::Polarity pol) noexcept {
  // 16 x size + 8 x polarity + 4 x direction + continuity
  return (16 * (maxValue == 8191) +
          8 * (pol == ValueTransformer::Polarity::bipolar) +
          4 * (dir == ValueTransformer::Direction::descending) +
          static_cast<size_t>(kind));
}

void fill(ValueTransformer::TransformArray& array, size_t maxValue, Generator gen, bool is_bipolar) noexcept {
  array.reserve(maxValue + 1);
  for (std::size_t value = 0; value <= maxValue; ++value) {
    Float transformed = gen(maxValue, value);
    if (is_bipolar) transformed = ::DSPHeaders::DSP::unipolarToBipolar(transformed);
    array.emplace_back(transformed);
  }
}

size_t transformsSize_ = 16 * 8 * 4 * 3;
std::vector<ValueTransformer::TransformArray> transforms_{transformsSize_};

const ValueTransformer::TransformArray&
ValueTransformer::selectActive(size_t maxValue, Kind kind, Direction dir, Polarity pol) noexcept {
  auto index = transformArrayIndex(maxValue, kind, dir, pol);
  if (transforms_[index].empty()) {
    fill(transforms_[index], maxValue, proc(kind, dir), pol == ValueTransformer::Polarity::bipolar);
  }
  return transforms_[index];
}
