// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include <iostream>
#include <sstream>

#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render::Voice::State;

namespace EntityMod = Entity::Modulator;

int Modulator::ValueProvider::ccValue(const State&, const MIDI::ChannelState& channelState) const noexcept {
  return channelState.continuousControllerValue(cc_);
}

int Modulator::ValueProvider::noteOnKey(const State& state, const MIDI::ChannelState&) const noexcept {
  return state.key();
}

int Modulator::ValueProvider::noteOnVelocity(const State& state, const MIDI::ChannelState&) const noexcept {
  return state.velocity();
}

int Modulator::ValueProvider::keyPressure(const State& state, const MIDI::ChannelState& channelState) const noexcept {
  return channelState.notePressure(state.key());
}

int Modulator::ValueProvider::channelPressure(const State&, const MIDI::ChannelState& channelState) const noexcept {
  return channelState.channelPressure();
}

int Modulator::ValueProvider::pitchWheelValue(const State&, const MIDI::ChannelState& channelState) const noexcept {
  return channelState.pitchWheelValue();
}

int Modulator::ValueProvider::pitchWheelSensitivity(const State&, const MIDI::ChannelState& channelState) const noexcept {
  return channelState.pitchWheelSensitivity();
}

Modulator::Modulator(const EntityMod::Modulator &configuration) noexcept
  : configuration_{configuration}, amount_{configuration.amount()},
    primaryValue_{makeValueProvider(configuration.source())},
    primaryTransform_{configuration.source()},
    secondaryValue_{makeValueProvider(configuration.amountSource())},
    secondaryTransform_{configuration.amountSource()}
{}

Modulator::ValueProvider
Modulator::makeValueProvider(const EntityMod::Source& source) noexcept
{
  using GI = EntityMod::Source::GeneralIndex;
  if (source.isContinuousController()) {
    return ValueProvider{&ValueProvider::ccValue, MIDI::ControlChange(source.ccIndex().value)};
  }
  switch (source.generalIndex()) {
    case GI::none: return ValueProvider{};
    case GI::noteOnKey: return ValueProvider{&ValueProvider::noteOnKey};
    case GI::noteOnVelocity: return ValueProvider{&ValueProvider::noteOnVelocity};
    case GI::keyPressure: return ValueProvider{&ValueProvider::keyPressure};
    case GI::channelPressure: return ValueProvider{&ValueProvider::channelPressure};
    case GI::pitchWheel: return ValueProvider{&ValueProvider::pitchWheelValue};
    case GI::pitchWheelSensitivity: return ValueProvider{&ValueProvider::pitchWheelSensitivity};
    default: return ValueProvider{}; // Not reached: `State::isUsable` rejects reserved sources
  }
}

std::string
Modulator::description() const
{
  std::ostringstream os;
  os << configuration().description();
  return os.str();
}

Float
Modulator::value(const State& state, const MIDI::ChannelState& channelState) const noexcept
{
  // SF2.01 8.2.1: with "No Controller" as the source, "the output of this controller module should be treated as if its
  // value were set to '1'. It should not be a means to turn off a modulator." The same holds for the amount source.
  Float transformedPrimary = primaryValue_.isActive() ? primaryTransform_(primaryValue_(state, channelState)) : 1_F;
  if (transformedPrimary == 0_F) return 0_F;

  // Obtain transformed secondary value.
  Float transformedSecondary = secondaryValue_.isActive() ? secondaryTransform_(secondaryValue_(state, channelState)) : 1_F;
  // SF2.01 9.5.1: "destination value += Transform(Amount * Map(primary source input) * Map(secondary source input))"
  return configuration_.transformer().transform(transformedPrimary * transformedSecondary * amount_);
}
