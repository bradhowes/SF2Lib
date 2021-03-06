// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Entity/Modulator/Transform.hpp"

namespace SF2::Entity::Modulator {

std::ostream&
operator<<(std::ostream& os, const Transform& value) noexcept
{
  return os << (value.kind() == Transform::Kind::linear ? "linear" : "absolute");
}

}
