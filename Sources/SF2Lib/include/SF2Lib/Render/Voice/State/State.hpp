// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <cassert>
#include <forward_list>
#include <iostream>
#include <list>
#include <numeric>
#include <vector>

#include "SF2Lib/Logger.hpp"
#include "SF2Lib/Types.hpp"
#include "SF2Lib/Entity/Generator/Generator.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Voice/State/GenValue.hpp"
#include "SF2Lib/Render/Voice/State/GenValueCollection.hpp"
#include "SF2Lib/Render/Voice/State/Modulator.hpp"

namespace SF2::Render::Voice::State {

class Config;

/**
 Generator values for a rendering voice. Most of the values originally come from generators defined in an SF2
 instrument or preset entity, with default values used if not explicitly set. Values can change over time via one or
 more modulators being applied to them, but the internal state is always read-only during the life of a Voice to which
 it uniquely belongs.

 The intent for the `State` class is to treat it just as a collection of generator values, and to let other classes
 perform transformations on the values held here. As such, generator-specific functionality should not exist here but
 in function-specific classes such as Envelope::Generator or Voice::Sample::Pitch.
 */
class State
{
public:
  using Amount = Entity::Generator::Amount;
  using Index = Entity::Generator::Index;
  using Definition = Entity::Generator::Definition;

  /**
   Create new state vector with a given sample rate.

   @param sampleRate the sample rate of audio being rendered
   @param channel the MIDI channel that is in control
   */
  State(Float sampleRate, const MIDI::ChannelState& channelState) :
  sampleRate_{sampleRate}, channelState_{channelState} {}

  /** Create new state vector for testing purposes.
   @param sampleRate the sample rate of audio being rendered
   @param channel the MIDI channel that is in control
   @param key the MIDI key to use
   @param velocity the MIDI velocity to use
   */
  State(Float sampleRate, const MIDI::ChannelState& channelState, int key, int velocity = 64) :
  sampleRate_{sampleRate}, channelState_{channelState}, eventKey_{key}, eventVelocity_{velocity}
  {
    setDefaults();
  }

  /**
   Set the sample rate to use for rendering

   @param sampleRate new value to use.
   */
  void setSampleRate(Float sampleRate) { sampleRate_ = sampleRate; }

  /**
   Configure the state to be used by a voice for sample rendering.
   */
  void prepareForVoice(const Config& config);

  /**
   Set a generator value. Should only be called with a value from an InstrumentZone. It can be set twice, once by a
   global instrument generator setting, and again by a non-global instrument generator setting, the latter one
   replacing the first.

   @param gen the generator to set
   @param value the value to use
   */
  void setValue(Index gen, int value) {
    log_.debug() << "setting " << Definition::definition(gen).name() << " = " << value << std::endl;
    gens_[gen].value = value;
  }

  /**
   Set a generator's adjustment value. Should only be called with a value from a PresetZone. It can be invoked twice,
   once by a global preset setting, and again by a non-global preset generator setting, the latter one replacing the
   first.

   @param gen the generator to set
   @param value the value to use
   */
  void setAdjustment(Index gen, int value) {
    log_.debug() << "adjust " << Definition::definition(gen).name() << " by " << value << std::endl;
    gens_[gen].adjustment = value;
  }

  /**
   Install a modulator.

   @param modulator the modulator to install
   */
  void addModulator(const Entity::Modulator::Modulator& modulator);

  /**
   Obtain a generator value without any adjustments from modulators. This is the sum of values set by zone generator
   definitions and so it is expressed as an integer. Most of the time, the `modulated` method is what is desired in
   order to account for any MIDI controller values.

   @param gen the index of the generator
   @returns configured value of the generator
   */
  int unmodulated(Index gen) const { return gens_[gen].unmodulated(); }

  /**
   Obtain a generator value that includes the changes added by attached modulators.

   @param gen the index of the generator
   @returns current value of the generator
   */
  Float modulated(Index gen) const { return gens_[gen].modulated(); }

  /// @returns MIDI key that started a voice to begin emitting samples. For DSP this is *not* what is desired. See
  /// `key` method below.
  int eventKey() const { return eventKey_; }

  /// @returns key value to use for DSP. A generator can force it to be fixed to a set value.
  int key() const {
    int key = unmodulated(Index::forcedMIDIKey);
    return key >= 0 ? key : eventKey_;
  }

  /// @returns velocity to use for DSP. A generator can force it to be fixed to a set value.
  int velocity() const {
    int velocity = unmodulated(Index::forcedMIDIVelocity);
    return velocity >= 0 ? velocity : eventVelocity_;
  }

  /// @returns the MIDI channel state associated with the rendering
  const MIDI::ChannelState& channelState() const { return channelState_; }

  /// @returns sample rate defined at construction
  Float sampleRate() const { return sampleRate_; }

private:

  void setDefaults();
  void linkModulators();

  const MIDI::ChannelState& channelState_;
  GenValueCollection gens_{};
  std::vector<Modulator> modulators_{};

  Float sampleRate_;
  int eventKey_;
  int eventVelocity_;

  inline static Logger log_{Logger::Make("Render.Voice", "State")};
};

} // namespace SF2::Render