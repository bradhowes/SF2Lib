// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cassert>
#include <cmath>
#include <functional>
#include <limits>

#include "SF2Lib/Logger.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

namespace SF2::Entity::Modulator { class Modulator; class Source; }

namespace SF2::MIDI { class Channel; }

namespace SF2::Render::Voice::State {

class State;

/**
 Render-side modulator that understands how to fetch source values that will be used to modulate voice state. Per the
 SF2 spec, a modulator does the following:

 - takes a source value (Sv) (eg from a MIDI controller) and transforms it into a unipolar or bipolar value
 - takes an 'amount' source value (Av) and transforms it into a unipolar or bipolar value
 - calculates and returns Sv * Av * amount (from SF2 Entity::Modulator)

 The Sv and Av transformations are done in the Transform class.

 The Modulator instances operate in a 'pull' fashion: a call to their `value()` method fetches source values, which may
 themselves be modulator instances. In this way, the `value()` method will always return the most up-to-date values.
 */
class Modulator {
public:

  /**
   Construct new modulator

   @param index the index of the entity in the zone
   @param configuration the entity configuration that defines the modulator
   @param state the voice state that can be used as a source for modulators
   */
  Modulator(size_t index, const Entity::Modulator::Modulator& configuration, const State& state);

  /// @returns current value of the modulator
  Float value() const {
    assert(isValid());

    // If there is no source for the modulator, it always returns 0.0 (no modulation).
    if (!sourceValue_.isValid()) return 0.0;

    // Obtain transformed value from source.
    Float value = sourceTransform_(sourceValue_());
    if (value == 0.0) return 0.0;

    // If there is a source for the scaling factor, apply its transformed value.
    if (amountScale_.isValid()) value *= amountTransform_(amountScale_());

    return value * amount_;
  }

  /// @returns configuration of the modulator from the SF2 file
  const Entity::Modulator::Modulator& configuration() const { return configuration_; }

  /// @returns index offset for the modulator
  size_t index() const { return index_; }

  /// Flag this modulator as being invalid.
  void flagInvalid() { index_ = std::numeric_limits<size_t>::max(); }

  /// @returns true if the modulator is valid.
  bool isValid() const { return index_ != std::numeric_limits<size_t>::max(); }

  /**
   Resolve the linking between two modulators. Configures this modulator to invoke the `value()` method of another to
   obtain an Sv value. Per spec, linking is NOT allowed for Av values. Also per spec, source values fall in range
   0-127 and are transformed into unipolar or bipolar ranges depending on their definition. This makes linking a bit
   strange: the 'source' modulator generates a unipolar or bipolar value per its definition, but unipolar is only
   useful in the linked case, and its `amount` must be 127 or 128 in order to get back a value that is reasonable to
   use as a source value for another modulator.

   @param modulator provider for an Sv to use for this modulator
   */
  void setSource(const Modulator& modulator);

  std::string description() const;

private:

  // Holds a pointer to member function that determines how to generate a value for a modulator. Holds state for the
  // member function to use, but not all pieces are used by all methods. Once set, these values normally do not change.
  // The one exception is when a Modulator is used to provide a value to another (aka linking).
  struct ValueProvider {
    using Proc = int (ValueProvider::*)() const;

    const State& state_;
    Proc proc_{nullptr};
    const int cc_{0};
    const Modulator* modulator_{nullptr};

    bool isValid() const { return proc_ != nullptr; }
    int operator()() const { return isValid() ? (this->*proc_)() : 0; }

    int ccValue() const;
    int key() const;
    int velocity() const;
    int keyPressure() const;
    int channelPressure() const;
    int pitchWheelValue() const;
    int pitchWheelSensitivity() const;
    int linked() const;
  };

  /**
   Obtain a generic callable entity that returns an integral value. This is used to obtain both the `source` and
   `amount` values, regardless of their actual source.

   @param source the modulator source definition from the SF2 file
   @param state the voice state that will be modulated
   @returns ValueProvider instance for obtaining the value
   */
  static ValueProvider makeValueProvider(const Entity::Modulator::Source& source, const State& state);

  const Entity::Modulator::Modulator& configuration_;
  size_t index_;
  int amount_;
  MIDI::ValueTransformer sourceTransform_;
  MIDI::ValueTransformer amountTransform_;

  ValueProvider sourceValue_;
  ValueProvider amountScale_;

  inline static Logger log_{Logger::Make("Render.Voice", "Modulator")};
};

} // namespace SF2::Render