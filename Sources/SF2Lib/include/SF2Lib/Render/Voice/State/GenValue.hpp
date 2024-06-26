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
   Set the generator value using a value from an Instrument.

   @param value the value to store
   */
  inline void setValue(int value) noexcept { value_ = value; cached_ = value; }

  /**
   Set the generator value from a live MIDI controller or AUParameterTree change.
   */
  inline void setLiveValue(int value) noexcept { value_ = value; cached_ = value + adjustment_ + mods_; }

  /**
   Set the generator's adjustment. This should only come from a preset zone.

   @param adjustment the value to store
   */
  inline void setAdjustment(int adjustment) noexcept { adjustment_ = adjustment; cached_ = value_ + adjustment_; }

  /**
   Set the total mod value

   @param value the value to assign
   */
  inline void setMods(Float value) noexcept { mods_ = value; cached_ = value_ + adjustment_ + mods_; }

  /**
   Add a value from a modulator

   @param value the value to add
   */
  inline void addMod(Float value) noexcept { mods_ += value; cached_ += value; }

  /// @returns current mods value
  inline Float mods() const noexcept { return mods_; }

  /// @returns current instrument/live value
  inline int instrumentValue() const noexcept { return value_; }

  /// @returns current preset value
  inline int presetValue() const noexcept { return adjustment_; }

  /// @returns generator value as defined by instrument zone (value) and preset zone (adjustment) only.
  inline int unmodulated() const noexcept { return value_ + adjustment_; }

  /// @returns generator value + modulations
  inline Float modulated() const noexcept { return cached_; }

private:
  int value_{0};
  int adjustment_{0};
  Float mods_{0_F};
  Float cached_{0_F};
};

}
