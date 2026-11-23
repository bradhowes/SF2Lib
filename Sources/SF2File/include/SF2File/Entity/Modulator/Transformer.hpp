// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include <cmath>
#include <iosfwd>

#include "DSPHeaders/Types.hpp"
#include "SF2Util/Types.hpp"

namespace SF2::Entity::Modulator {

/**
 Modulator value transformer (`sfModTransOper`). It is applied to the output of the modulator's multiplier, before the
 destination summing node (SF2.01 8.3, 9.5.1: `Transform(Amount * Map(primary) * Map(secondary))`). Known kinds:

 - linear (0): value is used as-is. The only kind defined by SF2.01.
 - absolute (2): the absolute value of the input. Added in SF2.04.

 Any other value is unknown, and SF2.01 10.3 says the modulator using it is to be ignored (see `isValid`).
 */
class Transformer {
public:
  enum struct Kind : uint16_t {
    linear = 0,
    absolute = 2
  };

  /**
   Constructor.

   @param kind the kind of transform to apply
   */
  Transformer(Kind kind = Kind::linear) noexcept : bits_{DSPHeaders::valueOf(kind)} {}

  /// @returns true if the raw value is a known transform kind
  bool isValid() const noexcept {
    return bits_ == DSPHeaders::valueOf(Kind::linear) || bits_ == DSPHeaders::valueOf(Kind::absolute);
  }

  /// @returns the kind of transform to apply. Only meaningful if `isValid()` is true.
  Kind kind() const noexcept { return Kind(bits_); }

  /// @returns the raw value read from the file
  uint16_t bits() const noexcept { return bits_; }

  /**
   Transform a value.

   @param value the value to transform
   @returns transformed value
   */
  template <std::floating_point T>
  T transform(T value) const noexcept { return kind() == Kind::absolute ? std::abs(value) : value; }

  /// @returns true if both have the same raw value
  bool operator ==(const Transformer& rhs) const noexcept { return bits_ == rhs.bits_; }

  friend std::ostream& operator<<(std::ostream& os, const Transformer& value);

private:
  uint16_t bits_;
};

} // end namespace SF2::Entity::Modulator
