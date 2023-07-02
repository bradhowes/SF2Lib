// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

namespace SF2::MIDI {

/**
 Collection of state values that pertains to a specific MIDI channel.
 */
class ChannelState {
public:

  inline constexpr static int CCMin = 0;
  inline constexpr static int CCMax = 127;

  /**
   Construct new channel.
   */
  ChannelState() noexcept {
    reset();
  }

  void reset() {
    continuousControllerValues_.fill(0);
    notePressureValues_.fill(0);
    nrpnValues_.zero();
    channelPressure_ = 0;
    pitchWheelValue_ = 0;
    pitchWheelSensitivity_ = 200;
    nrpnIndex_ = 0;

    sustainActive_ = false;
    sostenutoActive_ = false;
    activeDecoding_ = false;
  }

  /**
   Set the pressure for a given note. This should only apply for an actively-playing note, and not a new one which
   should use the velocity component.

   @param key the key (note) to set
   @param value the pressure value to record
   */
  void setNotePressure(int key, int value) {
    if (key < 0 || key > Note::Max) throw std::runtime_error("invalid key");
    notePressureValues_[static_cast<size_t>(key)] = value;
  }

  /**
   Get the pressure for a given key.

   @param key the key to get
   @returns the current pressure value for a key
   */
  int notePressure(int key) const {
    if (key < 0 or key > Note::Max) throw std::runtime_error("invalid key");
    return notePressureValues_[static_cast<size_t>(key)];
  }

  /**
   Set the channel pressure.

   @param value the pressure value to record
   */
  void setChannelPressure(int value) noexcept { channelPressure_ = value; }

  /// @returns the current channel pressure
  int channelPressure() const noexcept { return channelPressure_; }

  /**
   Set the pitch wheel value

   @param value the pitch wheel value
   */
  void setPitchWheelValue(int value) noexcept { pitchWheelValue_ = value; }

  /// @returns the current pitch wheel value
  int pitchWheelValue() const noexcept { return pitchWheelValue_; }

  /**
   Set the pitch wheel sensitivity value

   @param value the sensitivity value to record
   */
  void setPitchWheelSensitivity(int value) noexcept { pitchWheelSensitivity_ = value; }

  /// @returns the current pitch wheel sensitivity value
  int pitchWheelSensitivity() const noexcept { return pitchWheelSensitivity_; }

  /**
   Set a continuous controller value

   @param id the controller ID
   @param value the value to set for the controller
   */
  void setContinuousControllerValue(size_t id, int value) {
    if (id > 127) throw std::runtime_error("invalid CC ID");
    continuousControllerValues_[id] = value;
  }

  void setContinuousControllerValue(MIDI::ControlChange id, int value);

  /**
   Get a continuous controller value.

   @param id the controller ID to get
   @returns the controller value
   */
  int continuousControllerValue(int id) const {
    if (id < CCMin || id > CCMax) throw std::runtime_error("invalid CC ID");
    return continuousControllerValues_[static_cast<size_t>(id - CCMin)];
  }

  /**
   Get a continuous controller value.

   @param id the controller ID to get
   @returns the controller value
   */
  int continuousControllerValue(MIDI::ControlChange id) const noexcept {
    return continuousControllerValue(static_cast<int>(id));
  }

  int nrpnValue(Entity::Generator::Index index) const noexcept { return nrpnValues_[index]; }

  bool isActivelyDecoding() const noexcept { return activeDecoding_; }

  size_t nrpnIndex() const noexcept { return nrpnIndex_; }

private:
  using ContinuousControllerValues = std::array<int, CCMax - CCMin + 1>;
  using NotePressureValues = std::array<int, Note::Max + 1>;

  ContinuousControllerValues continuousControllerValues_{};
  NotePressureValues notePressureValues_{};
  Entity::Generator::GeneratorValueArray<int> nrpnValues_{};

  int channelPressure_{0};
  int pitchWheelValue_{0};
  int pitchWheelSensitivity_{200};
  size_t nrpnIndex_{0};
  
  bool sustainActive_{false};
  bool sostenutoActive_{false};
  bool activeDecoding_{false};
};

} // namespace SF2::MIDI
