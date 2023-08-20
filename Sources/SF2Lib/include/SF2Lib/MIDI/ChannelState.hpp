// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>

#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"
#include "SF2Lib/MIDI/Note.hpp"

namespace SF2::MIDI {

/**
 Collection of state values that pertains to a specific MIDI channel. Holds values for general MIDI controllers and for
 continuous controllers (CC). Also provides a way to translate NPRN values into a generator index, which can then be
 used to deposit modulator values for any of the defined sound font generators.
 */
class ChannelState {
public:
  inline constexpr static int maxPitchWheelValue = 8191;

  /**
   Construct new channel.
   */
  ChannelState() noexcept { reset(); }

  ChannelState(ChannelState&&) = default;

  /// Put channel state in original state.
  void reset() noexcept;

  /**
   Set the pressure for a given note. This should only apply for an actively-playing note, and not a new one which
   should use the velocity component.

   @param key the key (note) to set
   @param value the pressure value to record
   */
  void setNotePressure(int key, int value) {
    if (key < 0 || key > Note::Max) return;
    notePressureValues_[static_cast<size_t>(key)] = value;
  }

  /**
   Get the pressure for a given key.

   @param key the key to get
   @returns the current pressure value for a key
   */
  int notePressure(int key) const noexcept {
    if (key < 0 or key > Note::Max) return 0;
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
   Set the pitch wheel value. For MIDI v1 this is a 14-bit value [0-8191] and at rest, it should report out a value
   of 4096 which when mapped to bipolar range [-1 - 1) will give 0 as an output value.

   @param value the pitch wheel value
   */
  void setPitchWheelValue(int value) noexcept {
    pitchWheelValue_ = std::clamp(value, 0, maxPitchWheelValue);
  }

  /// @returns the current pitch wheel value
  int pitchWheelValue() const noexcept { return pitchWheelValue_; }

  /**
   Set the pitch wheel sensitivity value. Default is 200 cents which results in 2 note jump in either direction of the
   pitch wheel.

   @param value the sensitivity value to record
   */
  void setPitchWheelSensitivity(int value) noexcept { pitchWheelSensitivity_ = value; }

  /// @returns the current pitch wheel sensitivity value
  int pitchWheelSensitivity() const noexcept { return pitchWheelSensitivity_; }

  /**
   Set the continuous controller value.

   @param id the controller ID
   @param value the value to set for the controller
   */
  bool setContinuousControllerValue(MIDI::ControlChange id, int value) noexcept;

  /**
   Get a continuous controller value.

   @param cc the controller ID to get
   @returns the controller value
   */
  int continuousControllerValue(MIDI::ControlChange cc) const noexcept { return continuousControllerValues_[cc]; }

  /**
   Get the NRPN value for associated with a generator.

   @param index the generator ID to fetch
   @returns the NRPN value for the generator
   */
  int nrpnValue(Entity::Generator::Index index) const noexcept { return nrpnValues_[index]; }

  /// @returns true if currently decoding a generator index
  bool isActivelyDecoding() const noexcept { return activeDecoding_; }

  /// @returns the currently decoded generator index
  size_t nrpnIndex() const noexcept { return nrpnIndex_; }

  void dump() const noexcept;
  
private:
  using ContinuousControllerValues = EnumIndexableValueArray<int, ControlChange, 128>;
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
