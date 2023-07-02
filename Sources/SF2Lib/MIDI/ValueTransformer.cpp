// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <functional>

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

using namespace SF2;
using namespace SF2::MIDI;
using VT = ValueTransformer;
using TL = VT::TransformLookup;

TL VT::positiveLinear_ = VT::Make(VT::positiveLinear);
TL VT::positiveConcave_ = VT::Make(VT::positiveConcave);
TL VT::positiveConvex_ = VT::Make(VT::positiveConvex);
TL VT::positiveSwitched_ = VT::Make(VT::positiveSwitched);

TL VT::negativeLinear_ = VT::Make(VT::negativeLinear);
TL VT::negativeConcave_ = VT::Make(VT::negativeConcave);
TL VT::negativeConvex_ = VT::Make(VT::negativeConvex);
TL VT::negativeSwitched_ = VT::Make(VT::negativeSwitched);

TL VT::positiveLinearBipolar_ = VT::Make(VT::positiveLinear, true);
TL VT::positiveConcaveBipolar_ = VT::Make(VT::positiveConcave, true);
TL VT::positiveConvexBipolar_ = VT::Make(VT::positiveConvex, true);
TL VT::positiveSwitchedBipolar_ = VT::Make(VT::positiveSwitched, true);

TL VT::negativeLinearBipolar_ = VT::Make(VT::negativeLinear, true);
TL VT::negativeConcaveBipolar_ = VT::Make(VT::negativeConcave, true);
TL VT::negativeConvexBipolar_ = VT::Make(VT::negativeConvex, true);
TL VT::negativeSwitchedBipolar_ = VT::Make(VT::negativeSwitched, true);


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
