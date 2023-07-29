// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cmath>
#include <iosfwd>

#include "SF2Lib/Types.hpp"

namespace SF2::Entity::Modulator {

/**
 Modulator value transformer. The spec defines two types:

 - linear: value is used as-is
 - absolute: negative values are made positive before being used

 Currently, all modulators seem to use `linear`.
 */
class Transformer {
public:

  enum struct Kind {
    linear = 0,
    absolute = 2
  };

  Transformer() noexcept : bits_{0} {}

  /**
   Constructor

   @param bits the value that determines the type of transform to apply
   */
  explicit Transformer(uint16_t bits) noexcept : bits_{bits} {}

  /// @returns the kind of transform to apply
  Kind kind() const noexcept { return bits_ == 0 ? Kind::linear : Kind::absolute; }

  /**
   Transform a value.

   @param value the value to transform
   @returns transformed value
   */
  template <typename T>
  T transform(T value) const noexcept {
    switch (kind()) {
      case Kind::linear: return value;
      case Kind::absolute: return std::abs(value);
      default: throw "unexpected transform kind";
    }
  }

  friend std::ostream& operator<<(std::ostream& os, const Transformer& value) noexcept;

private:
  const uint16_t bits_;
};

} // end namespace SF2::Entity::Modulator
