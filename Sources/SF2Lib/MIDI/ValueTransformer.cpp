// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <functional>

#include "SF2Lib/ConstMath.hpp"
#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

using namespace SF2;
using namespace SF2::MIDI;
static constexpr size_t TableSize = ValueTransformer::TableSize;

static constexpr Float positiveLinear(size_t index) noexcept { return Float(index) / TableSize; }
static constexpr Float negativeLinear(size_t index) noexcept { return 1.0f - positiveLinear(index); }

static constexpr Float positiveConcave(size_t index) noexcept {
  return index == (TableSize - 1) ? 1.0 : -40.0 / 96.0 * ConstMath::log10((127.0 - index) / 127.0);
}

static constexpr Float negativeConcave(size_t index) noexcept {
  return index == 0.0 ? 1.0 : -40.0 / 96.0 * ConstMath::log10(index / 127.0);
}

static constexpr Float positiveConvex(size_t index) noexcept {
  return index == 0.0 ? 0.0 : 1.0 - -40.0 / 96.0 * ConstMath::log10(index / 127.0);
}

static constexpr Float negativeConvex(size_t index) noexcept {
  return index == (TableSize - 1) ? 0.0 : 1.0 - -40.0 / 96.0 * ConstMath::log10((127.0 - index) / 127.0);
}

static constexpr Float positiveSwitched(size_t index) noexcept { return index < TableSize / 2 ? 0.0 : 1.0; }
static constexpr Float negativeSwitched(size_t index) noexcept { return index < TableSize / 2 ? 1.0 : 0.0; }

template <typename F>
constexpr auto bipolar(F proc) { return [=](size_t index) { return DSP::unipolarToBipolar(proc(index)); }; }

static constexpr auto positiveLinear_ = ConstMath::make_array<Float, TableSize>(positiveLinear);
static constexpr auto positiveLinearBipolar_ = ConstMath::make_array<Float, TableSize>(bipolar(positiveLinear));
static constexpr auto negativeLinear_ = ConstMath::make_array<Float, TableSize>(negativeLinear);
static constexpr auto negativeLinearBipolar_ = ConstMath::make_array<Float, TableSize>(bipolar(negativeLinear));

static constexpr auto positiveConcave_ = ConstMath::make_array<Float, TableSize>(positiveConcave);
static constexpr auto positiveConcaveBipolar_ = ConstMath::make_array<Float, TableSize>(bipolar(positiveConcave));

static constexpr auto negativeConcave_ = ConstMath::make_array<Float, TableSize>(negativeConcave);
static constexpr auto negativeConcaveBipolar_ = ConstMath::make_array<Float, TableSize>(bipolar(negativeConcave));

static constexpr auto positiveConvex_ = ConstMath::make_array<Float, TableSize>(positiveConvex);
static constexpr auto positiveConvexBipolar_ = ConstMath::make_array<Float, TableSize>(bipolar(positiveConvex));

static constexpr auto negativeConvex_ = ConstMath::make_array<Float, TableSize>(negativeConvex);
static constexpr auto negativeConvexBipolar_ = ConstMath::make_array<Float, TableSize>(bipolar(negativeConvex));

static constexpr auto positiveSwitched_ = ConstMath::make_array<Float, TableSize>(positiveSwitched);
static constexpr auto positiveSwitchedBipolar_ = ConstMath::make_array<Float, TableSize>(bipolar(positiveSwitched));
static constexpr auto negativeSwitched_ = ConstMath::make_array<Float, TableSize>(negativeSwitched);
static constexpr auto negativeSwitchedBipolar_ = ConstMath::make_array<Float, TableSize>(bipolar(negativeSwitched));

ValueTransformer::ValueTransformer(Kind kind, Direction dir, Polarity pol) noexcept
: active_{selectActive(kind, dir, pol)} {}

const ValueTransformer::TransformArrayType& ValueTransformer::selectActive(Kind kind, Direction dir,
                                                                           Polarity pol) noexcept {
  if (pol == Polarity::unipolar) {
    switch (kind) {
      case Kind::linear: return dir == Direction::ascending ? positiveLinear_ : negativeLinear_;
      case Kind::concave: return dir == Direction::ascending ? positiveConcave_ : negativeConcave_;
      case Kind::convex: return dir == Direction::ascending ? positiveConvex_ : negativeConvex_;
      case Kind::switched: return dir == Direction::ascending ? positiveSwitched_ : negativeSwitched_;
    }
  }
  switch (kind) {
    case Kind::linear: return dir == Direction::ascending ? positiveLinearBipolar_ : negativeLinearBipolar_;
    case Kind::concave: return dir== Direction::ascending ? positiveConcaveBipolar_ : negativeConcaveBipolar_;
    case Kind::convex: return dir == Direction::ascending ? positiveConvexBipolar_ : negativeConvexBipolar_;
    case Kind::switched: return dir == Direction::ascending ? positiveSwitchedBipolar_ : negativeSwitchedBipolar_;
  }
}
