// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cmath>
#include <iosfwd>


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

  Transformer() noexcept : bits_{static_cast<uint16_t>(Kind::linear)} {}
  explicit Transformer(uint16_t bits) noexcept : bits_{bits} {}

  /// @returns the kind of transform to apply
  Kind kind() const noexcept { return Kind::linear; }

  /**
   Transform a value.

   @param value the value to transform
   @returns transformed value
   */
  template <typename T>
  T transform(T value) const noexcept { return value; }

  friend std::ostream& operator<<(std::ostream& os, const Transformer& value) noexcept;

private:
  uint16_t bits_;
};

} // end namespace SF2::Entity::Modulator
