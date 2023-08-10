// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <functional>
#include <iostream>

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

using namespace SF2;
using namespace SF2::MIDI;
using namespace DSPHeaders::ConstMath;

constexpr Float positiveLinear(size_t maxValue, size_t index) noexcept {
  return Float(index) / Float(maxValue + 1);
}

constexpr Float positiveConcave(size_t maxValue, size_t index) noexcept {
  return index == maxValue ? 1.0f : Float(-40.0) / Float(96.0) * log10((maxValue - index) / Float(maxValue));
}

constexpr Float positiveConvex(size_t maxValue, size_t index) noexcept {
  return index == 0 ? 0.0f : 1.0f + Float(40.0) / Float(96.0) * log10(index / Float(maxValue));
}

constexpr Float positiveSwitched(size_t maxValue, size_t index) noexcept {
  return index <= maxValue / 2 ? 0.0 : 1.0;
}

constexpr Float negativeLinear(size_t maxValue, size_t index) noexcept {
  return 1.0f - positiveLinear(maxValue, index);
}

constexpr Float negativeConcave(size_t maxValue, size_t index) noexcept {
  return index == 0 ? 1.0f : Float(-40.0) / Float(96.0) * log10(index / Float(maxValue));
}

constexpr Float negativeConvex(size_t maxValue, size_t index) noexcept {
  return index == maxValue ? 0.0f : 1.0f + Float(40.0) / Float(96.0) * log10((maxValue - index) / Float(maxValue));
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
  return (16 * (maxValue == ChannelState::maxPitchWheelValue) +
          8 * (pol == ValueTransformer::Polarity::bipolar) +
          4 * (dir == ValueTransformer::Direction::descending) +
          static_cast<size_t>(kind));
}

void fill(ValueTransformer::TransformArray& array, size_t maxValue, Generator gen, bool is_bipolar) noexcept {
  array.reserve(maxValue + 1);
  for (std::size_t value = 0; value <= maxValue; ++value) {
    Float transformed = gen(maxValue, value);
    if (is_bipolar) transformed = Float(::DSPHeaders::DSP::unipolarToBipolar(transformed));
    array.emplace_back(transformed);
  }
}

std::vector<ValueTransformer::TransformArray> buildAll() {
  size_t transformsSize_ = 32;
  std::vector<ValueTransformer::TransformArray> transforms{transformsSize_};
  for (int M = 0; M < 2; ++M) {
    auto maxValue = size_t(M * (8191 - 127) + 127);
    for (int P = 0; P < 2; ++P ) {
      auto pol{ValueTransformer::Polarity(P)};
      for (int D = 0; D < 2; ++D) {
        auto dir{ValueTransformer::Direction(D)};
        for (int K = 0; K < 4; ++K) {
          auto kind{ValueTransformer::Kind(K)};
          auto index = transformArrayIndex(maxValue, kind, dir, pol);
          fill(transforms[index], maxValue, proc(kind, dir), P);
        }
      }
    }
  }
  return transforms;
}

static std::vector<ValueTransformer::TransformArray> transforms_{buildAll()};

const ValueTransformer::TransformArray&
ValueTransformer::selectTransformArray(size_t maxValue, Kind kind, Direction dir, Polarity pol) noexcept {
  auto index = transformArrayIndex(maxValue, kind, dir, pol);
  return transforms_[index];
}
