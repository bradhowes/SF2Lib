// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <list>
#include <forward_list>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/Utils/ListNodeAllocator.hpp"

namespace SF2::Render::Voice::State {

/**
 A runtime generator value. Contains three components:

 - value -- set by an instrument zone generator
 - adjustment -- added to by a preset zone generator
 - sumMods -- contributions from modulators
 */
struct GenValue {
  using Allocator = Utils::ListNodeAllocator<size_t>;
  using ModulatorIndexLinkedList = std::list<size_t, Allocator>;

  // Theoretically, G generators can have M linked modulators, and each of these can appear in V voices, so worst-case
  // is we have to allow for G * M * V links. We do not want to allocate these in the render thread so we do so at start
  // but this is a waste of bytes. Also, we do not know the number of voices to support until `Render::Engine` is
  // constructed, so we make due with hard-coded values.
  static constexpr auto V = 256;
  static constexpr auto G = int(SF2::Entity::Generator::Index::numValues);
  static constexpr auto M = 16;
  inline static Allocator allocator = Allocator(V * G * M);

  /**
   Construct a new value
   */
  GenValue() noexcept : mods{allocator} {}

  /// @returns generator value as defined by zones (no modulators).
  int unmodulated() const noexcept { return value + adjustment; }

  /// @returns generator value that includes modulator contributions
  Float modulated() const noexcept { return unmodulated() + sumMods + nrpn; }

  int value{0};
  int adjustment{0};
  Float sumMods{0.0};
  Float nrpn{0};

  ModulatorIndexLinkedList mods{allocator};
};

}
