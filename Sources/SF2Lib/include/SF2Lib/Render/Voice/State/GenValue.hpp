// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render::Voice::State {

class State;

/**
 A runtime generator value. Contains three components:

 - value -- set by an instrument zone generator
 - adjustment -- added to by a preset zone generator
 - mods -- added by a linked modulator
 */
struct GenValue {

  /**
   Set the generator value. This should only come from an instrument zone.

   @param value the value to store
   */
  void setValue(int value) noexcept { value_ = value; cached_ = value; }

  /**
   Set the generator's adjustment. This should only come from a preset zone.

   @param adjustment the value to store
   */
  void setAdjustment(int adjustment) noexcept { adjustment_ = adjustment; cached_ = value_ + adjustment_; }

  void setMods(Float value) noexcept { mods_ = value; cached_ = value_ + adjustment_ + mods_; }

  /**
   Add a value from a modulator

   @param value the value to add
   */
  void addMod(Float value) noexcept { mods_ += value; cached_ += value; }

  constexpr Float mods() const noexcept { return mods_; }

  constexpr int instrumentValue() const noexcept { return value_; }

  constexpr int presetValue() const noexcept { return adjustment_; }

  /// @returns generator value as defined by instrument zone (value) and preset zone (adjustment).
  constexpr int unmodulated() const noexcept { return value_ + adjustment_; }

  /// @returns generator value + modulations
  constexpr Float modulated() const noexcept { return cached_; }

private:
  int value_{0};
  int adjustment_{0};
  Float mods_{0_F};
  Float cached_{0_F};
};

}
