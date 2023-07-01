// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <array>

#include "SF2Lib/Entity/Generator/Generator.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Voice/State/GenValue.hpp"

namespace SF2::Render::Voice::State {

/**
 Fixed array of GenValue instances, one for each of the defined SF2 generators.
 */
struct GenValueCollection {
  using Index = Entity::Generator::Index;

  GenValueCollection() { array_.fill(GenValue()); }
  
  /**
   Reset all values to zero.
   */
  void zero() noexcept { array_.fill(GenValue()); }

private:
  Entity::Generator::GeneratorValueArray<GenValue> array_{};
};

}
