// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cmath>
#include <iosfwd>

#include "SF2Lib/Types.hpp"

namespace SF2::Entity::Modulator {

/**
 Modulator value transformer. The spec defines one type:

 - linear: value is used as-is
 */
class Transformer {
public:

  enum struct Kind : uint16_t {
    linear = 0
  };

  /**
   Default constructor for a linear transformer.
   */
  Transformer() noexcept : bits_{SF2::valueOf(Kind::linear)} {}

  /// @returns the kind of transform to apply
  Kind kind() const noexcept { return Kind::linear; }

  uint16_t bits() const noexcept { return bits_; }

  /**
   Transform a value.

   @param value the value to transform
   @returns transformed value
   */
  template <std::floating_point T>
  T transform(T value) const noexcept { return value; }

  friend std::ostream& operator<<(std::ostream& os, const Transformer& value) noexcept;

private:
  uint16_t bits_;
};

} // end namespace SF2::Entity::Modulator
