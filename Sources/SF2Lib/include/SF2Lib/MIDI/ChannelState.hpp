// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cmath>

#include "SF2File/Entity/Generator/Index.hpp"
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
  /// Largest value of the 14-bit MIDI v1 pitch wheel. The wheel at rest reports `(maxPitchWheelValue + 1) / 2` (8192).
  inline static const int maxPitchWheelValue = 16'383;

  /**
   Construct new channel.
   */
  ChannelState() noexcept { reset(); }

  ChannelState(ChannelState&&) noexcept = default;

  /// Put channel state in original state.
  void reset() noexcept;

  /**
   Set the pressure for a given note. This should only apply for an actively-playing note, and not a new one which
   should use the velocity component.

   @param key the key (note) to set
   @param value the pressure value to record
   */
  inline void setNotePressure(int key, uint8_t value) noexcept {
    checkedVectorIndexing(notePressureValues_, key) = value;
  }

  /**
   Get the pressure for a given key.

   @param key the key to get
   @returns the current pressure value for a key
   */
  inline uint8_t notePressure(int key) const noexcept { return checkedVectorIndexing(notePressureValues_, key); }

  /**
   Set the channel pressure.

   @param value the pressure value to record
   */
  inline void setChannelPressure(uint8_t value) noexcept { channelPressure_ = value; }

  /// @returns the current channel pressure
  inline uint8_t channelPressure() const noexcept { return channelPressure_; }

  /**
   Set the pitch wheel value. For MIDI v1 this is a 14-bit value [0-16383] and at rest, it should report out a value
   of 8192 (0x2000) which when mapped to bipolar range [-1 - 1) will give 0 as an output value.

   @param value the pitch wheel value
   */
  inline void setPitchWheelValue(int value) noexcept {
    pitchWheelValue_ = std::clamp(value, 0, maxPitchWheelValue);
  }

  /// @returns the current pitch wheel value
  inline int pitchWheelValue() const noexcept { return pitchWheelValue_; }

  /**
   Set the pitch wheel sensitivity in semitones. The default is 2, a 2-semitone bend in either direction. This is the
   value of the "pitch wheel sensitivity" modulator source (SF2.01 8.2.1, index 16). Over MIDI it is set with RPN 0
   (see `setContinuousControllerValue`).

   @param value the sensitivity in semitones (0-127)
   */
  inline void setPitchWheelSensitivity(int value) noexcept { pitchWheelSensitivity_ = value; }

  /**
   Respond to MIDI Reset All Controllers (CC 121) as described by MIDI RP-015: modulation, expression, the pedals
   (64-67), pitch bend, channel and key pressure, and the RPN/NRPN numbers are reset. Bank select, volume, pan, the
   sound and effects controllers, and RPN/NRPN values (e.g. pitch wheel sensitivity) are kept. Unlike `reset` this
   is not a power-on reset.
   */
  void resetControllers() noexcept;

  /// @returns the current pitch wheel sensitivity value
  inline int pitchWheelSensitivity() const noexcept { return pitchWheelSensitivity_; }

  /**
   Set the continuous controller value.

   @param id the controller ID
   @param value the value to set for the controller
   */
  bool setContinuousControllerValue(MIDI::ControlChange id, uint8_t value) noexcept;

  /**
   Get a continuous controller value.

   @param cc the controller ID to get
   @returns the controller value
   */
  inline uint8_t continuousControllerValue(MIDI::ControlChange cc) const noexcept {
    return continuousControllerValues_[cc];
  }

  /**
   Get the NRPN value for associated with a generator.

   @param index the generator ID to fetch
   @returns the NRPN value for the generator
   */
  inline int nrpnValue(Entity::Generator::Index index) const noexcept { return nrpnValues_[index]; }

  /// @returns true if currently decoding a generator index
  inline bool isActivelyDecoding() const noexcept { return activeDecoding_; }

  /// @returns the currently decoded generator index
  inline size_t nrpnIndex() const noexcept { return nrpnIndex_; }

  /**
   State of control pedals -- those that have ON/OFF values.
   */
  struct PedalState {
    bool sustainPedalActive{false};
    bool sostenutoPedalActive{false};
    bool softPedalActive{false};
  };

  /// @returns current state of control pedals.
  inline PedalState pedalState() const noexcept { return pedalState_; }

  void dump() const noexcept;

private:
  using ContinuousControllerValues = EnumIndexableValueArray<uint8_t, ControlChange, 128>;
  using NotePressureValues = std::array<uint8_t, Note::Max + 1>;

  bool decodeNRPN(MIDI::ControlChange cc, uint8_t value) noexcept;

  /// Apply a Data Entry MSB value to the currently selected RPN, if it is one we support.
  void applyRPNDataEntry(uint8_t value) noexcept;

  ContinuousControllerValues continuousControllerValues_{};
  NotePressureValues notePressureValues_{};
  Entity::Generator::GeneratorValueArray<int> nrpnValues_{};

  uint8_t channelPressure_{0};
  int pitchWheelValue_{0};
  int pitchWheelSensitivity_{2};
  size_t nrpnIndex_{0};
  PedalState pedalState_{false, false, false};
  bool activeDecoding_{false};

  /// True if an RPN was selected more recently than an NRPN, and is not the "RPN null" (127/127). Unlike NRPN decoding,
  /// unrelated controllers do not clear this: an RPN stays selected until another RPN or NRPN is selected.
  bool rpnSelected_{false};
};

} // namespace SF2::MIDI
