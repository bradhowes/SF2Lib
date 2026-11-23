// Copyright © 2026 Brad Howes. All rights reserved.

#include "DSPHeaders/Types.hpp"
#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Engine/ParameterAddress.hpp"

#pragma once

namespace SF2::Render::Engine {

// TODO: integrate this into Engine as a template parameter

struct traits {
  static constexpr AUValue minLastLoadFinished{AUValue(-1.0e-4)};
  static constexpr AUValue maxLastLoadFinished{AUValue(1.0e+6)};
  static constexpr AUValue lastLoadFinishedChange{AUValue(0.0001)};

  static constexpr size_t maxVoiceCount{128};

  /// Number of engine parameters to be found in the AUParameterTree.
  static constexpr size_t engineParameterCount = (DSPHeaders::valueOf(ParameterAddress::lastParameterAddressPlusOne) -
                                                         DSPHeaders::valueOf(ParameterAddress::firstParameterAddress));

  /// Total number of engine parameters to be found in the AUParameterTree (not exact due to unused indices in the list of
  /// SF2 generators)
  static constexpr size_t parameterTreeSize = DSPHeaders::valueOf(Entity::Generator::Index::numValues) + engineParameterCount;
};

}
