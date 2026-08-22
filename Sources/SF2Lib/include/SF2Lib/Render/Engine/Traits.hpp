// Copyright © 2026 Brad Howes. All rights reserved.

#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Engine/ParameterAddress.hpp"

#pragma once

namespace SF2::Render::Engine {

// TODO: integrate this into Engine as a template parameter

struct traits {
  static inline constexpr AUValue minLastLoadFinished{AUValue(-1.0e-4)};
  static inline constexpr AUValue maxLastLoadFinished{AUValue(1.0e+6)};
  static inline constexpr AUValue lastLoadFinishedChange{AUValue(0.0001)};

  static inline constexpr size_t maxVoiceCount{128};

  /// Number of engine parameters to be found in the AUParameterTree.
  static inline constexpr size_t engineParameterCount = (valueOf(ParameterAddress::lastParameterAddressPlusOne) -
                                                         valueOf(ParameterAddress::firstParameterAddress));

  /// Total number of engine parameters to be found in the AUParameterTree (not exact due to unused indices in the list of
  /// SF2 generators)
  static inline constexpr size_t parameterTreeSize = valueOf(Entity::Generator::Index::numValues) + engineParameterCount;
};

}
