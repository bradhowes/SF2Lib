// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <vector>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/Entity/Modulator/Source.hpp"

namespace SF2::MIDI {

/**
 Transforms MIDI v1.0 controller values into various ranges for use in a modulator.
 */
class ValueTransformer {
public:
  using Float = SF2::Float;
  using TransformArray = std::vector<Float>;

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
    bipolar
  };

  /// Direction controls the ordering of the min/max values.
  enum struct Direction {
    ascending = 0,
    descending
  };

  /**
   Create new value transformer from an SF2 modulator source definition.

   @param source the source definition to use
   */
  explicit ValueTransformer(const Entity::Modulator::Source& source) noexcept :
  active_{selectTransformArray(size_t(source.controllerRange()) - 1, Kind(source.type()),
                               source.isPositive() ? Direction::ascending : Direction::descending,
                               source.isUnipolar() ? Polarity::unipolar : Polarity::bipolar)}
  {}

  /**
   Transform a controller value into a modulation value.

   @param controllerValue value to convert between 0 and 127
   @returns transformed value
   */
  auto operator()(int controllerValue) const noexcept {
    return checkedVectorIndexing(active_, std::clamp(controllerValue, 0, int(active_.size() - 1)));
  }

private:

  /**
   Locate the right table to use based on the transformation, direction, and polarity.

   @param maxValue the largest value that the controller will provide (127 or 8191 for MIDI v1)
   @param kind the transformation function to apply
   @param direction the min/max ordering to use
   @param polarity the lower bound of the transformed result
   @returns reference to table to use for MIDI value transformations.
   */
  static const TransformArray& selectTransformArray(size_t maxValue, Kind kind, Direction direction,
                                                    Polarity polarity) noexcept;

  const TransformArray& active_;
};

} // namespace SF2::MIDI
