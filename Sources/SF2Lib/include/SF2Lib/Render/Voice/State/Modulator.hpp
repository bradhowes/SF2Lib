// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <iostream>

#include "SF2Lib/Entity/Modulator/Modulator.hpp"
#include "SF2Lib/Entity/Modulator/Source.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

namespace SF2::MIDI { class Channel; }

namespace SF2::Render::Voice::State {

class State;

/**
 Render-side modulator that understands how to fetch source values that will be used to modulate voice state. Per the
 SF2 spec, a modulator does the following:

 - takes a source value (Sv) (eg from a MIDI controller) and transforms it into a unipolar or bipolar value
 - takes an 'amount' source value (Av) and transforms it into a unipolar or bipolar value
 - calculates and returns Sv * Av * amount (from SF2 Entity::Modulator)

 The Sv and Av transformations are done in the Transformer class.

 The Modulator instances operate in a 'pull' fashion: a call to their `value()` method fetches source values.
 In this way, the `value()` method will always return the most up-to-date values.
 */
class Modulator {
public:

  /**
   Construct new modulator

   @param configuration the entity configuration that defines the modulator
   */
  Modulator(const Entity::Modulator::Modulator& configuration) noexcept;

  /**
   Acquire the amount from the given configuration. This is the only change we can make since per spec, modulators are
   equivalent (and thus overridable) when they have the same sources and transform.

   @param configuration the SF2 entity to take the amount from
   */
  void takeAmountFrom(const Entity::Modulator::Modulator& configuration) noexcept
  {
    amount_ = configuration.amount();
  }

  /**
   Calculate the modulator's value.

   @param state the voice state that is used as a source of values for the modulator

   @returns current value of the modulator
   */
  Float value(const State& state) const noexcept;

  /// @returns configuration of the modulator from the SF2 file. This is used to allow for comparisons between
  /// modulators.
  const Entity::Modulator::Modulator& configuration() const noexcept { return configuration_; }

  /// @returns the generator index that this modulator affects.
  Entity::Generator::Index destination() const noexcept { return configuration_.generatorDestination(); }

  /// @returns a textual description of the modulator.
  std::string description() const noexcept;

private:

  // Holds a pointer to member function that determines how to generate a value for a modulator.
  struct ValueProvider {
    using Proc = int (ValueProvider::*)(const State&) const;

    Proc proc_{nullptr};
    const MIDI::ControlChange cc_{0};

    bool isActive() const noexcept { return proc_ != nullptr; }
    int operator()(const State& state) const noexcept { return (this->*proc_)(state); }

    int ccValue(const State&) const noexcept;
    int noteOnKey(const State&) const noexcept;
    int noteOnVelocity(const State&) const noexcept;
    int keyPressure(const State&) const noexcept;
    int channelPressure(const State&) const noexcept;
    int pitchWheelValue(const State&) const noexcept;
    int pitchWheelSensitivity(const State&) const noexcept;
  };

  /**
   Obtain a generic callable entity that returns an integral value. This is used to obtain both the `source` and
   `amount` values, regardless of their actual source.

   @param source the modulator source definition from the SF2 file
   @returns ValueProvider instance for obtaining the value
   */
  static ValueProvider makeValueProvider(const Entity::Modulator::Source& source) noexcept;

  const Entity::Modulator::Modulator& configuration_;
  int amount_;

  const ValueProvider primaryValue_;
  const MIDI::ValueTransformer primaryTransform_;
  const ValueProvider secondaryValue_;
  const MIDI::ValueTransformer secondaryTransform_;
};

} // namespace SF2::Render
