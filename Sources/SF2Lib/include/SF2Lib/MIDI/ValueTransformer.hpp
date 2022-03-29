// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <cassert>
#include <cmath>
#include <array>
#include <iosfwd>

#include "DSPHeaders/ConstMath.hpp"

#include "SF2Lib/Types.hpp"
#include "SF2Lib/Entity/Modulator/Source.hpp"

// namespace SF2::DSP { namespace Tables { struct Generator; } }
namespace SF2::MIDI {

/**
 Transforms MIDI controller domain values (between 0 and 127) into various ranges. This currently only works with the
 `coarse` controller values.

 The conversion is done via a collection of lookup tables that map between [0, 127] and [0, 1] or [-1, 1].
 */
class ValueTransformer {
public:
  using Float = SF2::Float;
  inline constexpr static int Min = 0;
  inline constexpr static int Max = 127;
  inline constexpr static size_t TableSize = Max + 1;
  using TransformArrayType = std::array<Float, TableSize>;

  /**
   Kind specifies the curvature of the MIDI value transformation function.
   - linear -- straight line from min to 1.0
   - concave -- curved line that slowly increases in value and then accelerates in change until reaching 1.
   - convex -- curved line that rapidly increases in value and then decelerates in change until reaching 1.
   - switched -- emits 0 for control values <= 64, and 1 for those > 64.

   NOTE: keep raw values aligned with Entity::Modulator::Source::ContinuityType.
   */
  enum struct Kind {
    linear = 0,
    concave,
    convex,
    switched
  };

  /// Polarity determines the lower bound: unipolar = 0, bipolar = -1.
  enum struct Polarity {
    unipolar = 0,
    bipolar = 1
  };

  /// Direction controls the ordering of the min/max values.
  enum struct Direction {
    ascending = 0,
    descending = 1
  };

  /// Domain controls how many values there are in the domain. Some domains start at 1 while others start at 0.
  enum struct Domain {
    zeroBased = 0,
    oneBased = 1
  };

  /**
   Create new value transformer from an SF2 modulator source definition

   @param source the source definition to use
   */
  explicit ValueTransformer(const Entity::Modulator::Source& source) noexcept :
  ValueTransformer(Kind(source.type()), source.isMinToMax() ? Direction::ascending : Direction::descending,
                   source.isUnipolar() ? Polarity::unipolar : Polarity::bipolar)
  {}

  /**
   Convert a controller value.

   @param controllerValue value to convert between 0 and 127
   @returns transformed value
   */
  Float operator()(int controllerValue) const noexcept {
    return Float(active_[size_t(std::clamp<int>(controllerValue, 0, Max))]);
  }

private:

  /**
   Create new value transformer.

   @param kind mapping operation from controller domain to value range
   @param direction ordering from min to max
   @param polarity range lower and upper bounds
   */
  ValueTransformer(Kind kind, Direction direction, Polarity polarity) noexcept;

  /**
   Locate the right table to use based on the transformation, direction, and polarity.

   @param kind the transformation function to apply
   @param direction the min/max ordering to use
   @param polarity the lower bound of the transformed result
   @returns reference to table to use for MIDI value transformations.
   */
  static const TransformArrayType& selectActive(Kind kind, Direction direction, Polarity polarity) noexcept;

  const TransformArrayType& active_;
};

} // namespace SF2::MIDI
