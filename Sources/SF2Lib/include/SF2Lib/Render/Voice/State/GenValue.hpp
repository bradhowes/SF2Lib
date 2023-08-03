// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <vector>

#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render::Voice::State {

class State;

/**
 A runtime generator value. Contains four components:

 - value -- set by an instrument zone generator
 - adjustment -- added to by a preset zone generator
 */
struct GenValue {

  /**
   Construct a new value
   */
  GenValue() = default;

  /**
   Set the generator value. This should only come from an instrument zone.

   @param value the value to store
   */
  void setValue(int value) noexcept { value_ = value; }

  /**
   Set the generator's adjustment. This should only come from a preset zone.

   @param adjustment the value to store
   */
  void setAdjustment(int adjustment) noexcept { adjustment_ = adjustment; }

  /**
   Assign a modulator to this generator's value.

   @param index the index of the modulator found in voice's state.
   */
  void addModulator(size_t index) noexcept { mods_.push_back(index); }

  /// @returns generator value as defined by instrument zone (value) and preset zone (adjustment).
  int value() const noexcept { return value_ + adjustment_; }

  Float sumMods(const std::vector<Modulator>& modulators) const noexcept {
    if (mods_.empty()) return 0.0f;
    Float value = 0.0f;
    for (auto index : mods_) {
      value += modulators[index].value();
    }
    return value;
  }

private:
  int value_{0};
  int adjustment_{0};
  std::vector<size_t> mods_{};
};

}
