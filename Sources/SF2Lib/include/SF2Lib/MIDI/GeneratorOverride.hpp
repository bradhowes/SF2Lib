// Copyright © 2025 Brad Howes. All rights reserved.

#pragma once

#include <vector>

namespace SF2::MIDI {

struct GeneratorOverride {
  short index;
  short value;
};

using GeneratorOverrideVector = std::vector<GeneratorOverride>;

} // namespace SF2::MIDI
