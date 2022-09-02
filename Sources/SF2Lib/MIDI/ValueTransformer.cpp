// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <functional>

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

using namespace SF2;
using namespace SF2::MIDI;
static constexpr size_t TableSize = ValueTransformer::TableSize;

static constexpr Float positiveLinear(size_t index) noexcept { return Float(index) / TableSize; }

static constexpr Float positiveConcave(size_t index) noexcept {
  return index == (TableSize - 1) ? 1.0 : -40.0 / 96.0 * DSPHeaders::ConstMath::log10((127.0 - index) / 127.0);
}

static constexpr Float positiveConvex(size_t index) noexcept {
  return index == 0.0 ? 0.0 : 1.0 - -40.0 / 96.0 * DSPHeaders::ConstMath::log10(index / 127.0);
}

static constexpr Float positiveSwitched(size_t index) noexcept { return index < TableSize / 2 ? 0.0 : 1.0; }

static constexpr Float negativeLinear(size_t index) noexcept { return 1.0f - positiveLinear(index); }

static constexpr Float negativeConcave(size_t index) noexcept {
  return index == 0.0 ? 1.0 : -40.0 / 96.0 * DSPHeaders::ConstMath::log10(index / 127.0);
}

static constexpr Float negativeConvex(size_t index) noexcept {
  return index == (TableSize - 1) ? 0.0 : 1.0 - -40.0 / 96.0 * DSPHeaders::ConstMath::log10((127.0 - index) / 127.0);
}

static constexpr Float negativeSwitched(size_t index) noexcept { return index < TableSize / 2 ? 1.0 : 0.0; }

// Generate lookup tables for the various transforms defined in SF2 spec. Each function is used twice, once to generate
// a table of unipolar (0-1) values, and again with the `bipolar` adapter to generate values from -1 to +1.

namespace {

using Generator = Float(*)(size_t);

static constexpr std::array<Float, TableSize> make_array(Generator gen, bool is_bipolar = false) noexcept {
  std::array<Float, TableSize> table = {};
  for (std::size_t i = 0; i != TableSize; ++i) {
    Float value = gen(i);
    if (is_bipolar) value = DSPHeaders::DSP::unipolarToBipolar(value);
    table[i] = value;
  }
  return table;
}
}

static constexpr auto positiveLinear_ = make_array(positiveLinear);
static constexpr auto positiveConcave_ = make_array(positiveConcave);
static constexpr auto positiveConvex_ = make_array(positiveConvex);
static constexpr auto positiveSwitched_ = make_array(positiveSwitched);

static constexpr auto negativeLinear_ = make_array(negativeLinear);
static constexpr auto negativeConcave_ = make_array(negativeConcave);
static constexpr auto negativeConvex_ = make_array(negativeConvex);
static constexpr auto negativeSwitched_ = make_array(negativeSwitched);

static constexpr auto positiveLinearBipolar_ = make_array(positiveLinear, true);
static constexpr auto positiveConcaveBipolar_ = make_array(positiveConcave, true);
static constexpr auto positiveConvexBipolar_ = make_array(positiveConvex, true);
static constexpr auto positiveSwitchedBipolar_ = make_array(positiveSwitched, true);

static constexpr auto negativeLinearBipolar_ = make_array(negativeLinear, true);
static constexpr auto negativeConcaveBipolar_ = make_array(negativeConcave, true);
static constexpr auto negativeConvexBipolar_ = make_array(negativeConvex, true);
static constexpr auto negativeSwitchedBipolar_ = make_array(negativeSwitched, true);

const ValueTransformer::TransformArrayType&
ValueTransformer::selectActive(Kind kind, Direction dir, Polarity pol) noexcept {
  if (pol == Polarity::unipolar) {
    switch (kind) {
      case Kind::linear: return dir == Direction::ascending ? positiveLinear_ : negativeLinear_;
      case Kind::concave: return dir == Direction::ascending ? positiveConcave_ : negativeConcave_;
      case Kind::convex: return dir == Direction::ascending ? positiveConvex_ : negativeConvex_;
      case Kind::switched: return dir == Direction::ascending ? positiveSwitched_ : negativeSwitched_;
    }
  } else {
    switch (kind) {
      case Kind::linear: return dir == Direction::ascending ? positiveLinearBipolar_ : negativeLinearBipolar_;
      case Kind::concave: return dir== Direction::ascending ? positiveConcaveBipolar_ : negativeConcaveBipolar_;
      case Kind::convex: return dir == Direction::ascending ? positiveConvexBipolar_ : negativeConvexBipolar_;
      case Kind::switched: return dir == Direction::ascending ? positiveSwitchedBipolar_ : negativeSwitchedBipolar_;
    }
  }
}

ValueTransformer::ValueTransformer(Kind kind, Direction dir, Polarity pol) noexcept
: active_{selectActive(kind, dir, pol)}
{
  ;
}
