// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>
#include <sstream>

#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render::Voice::State;

namespace EntityMod = Entity::Modulator;

int Modulator::ValueProvider::ccValue(const State& state) const noexcept {
  auto value = state.channelState().continuousControllerValue(cc_);
  // std::cout << "ValueProvider CC " << valueOf(cc_) << " value: " << value << "\n";
  return value;
}

int Modulator::ValueProvider::noteOnKey(const State& state) const noexcept {
  auto value = state.key();
  // std::cout << "ValueProvider key " << value << "\n";
  return value;
}

int Modulator::ValueProvider::noteOnVelocity(const State& state) const noexcept {
  auto value = state.velocity();
  // std::cout << "ValueProvider vel " << value << "\n";
  return value;
}

int Modulator::ValueProvider::keyPressure(const State& state) const noexcept {
  auto value = state.channelState().notePressure(state.key());
  // std::cout << "ValueProvider keyPressure " << state.key() << " " << value << "\n";
  return value;
}

int Modulator::ValueProvider::channelPressure(const State& state) const noexcept {
  auto value = state.channelState().channelPressure();
  // std::cout << "ValueProvider channelPressure " << value << "\n";
  return value;
}

int Modulator::ValueProvider::pitchWheelValue(const State& state) const noexcept {
  auto value = state.channelState().pitchWheelValue();
  // std::cout << "ValueProvider pitchWheelValue " << value << "\n";
  return value;
}

int Modulator::ValueProvider::pitchWheelSensitivity(const State& state) const noexcept {
  auto value = state.channelState().pitchWheelSensitivity();
  // std::cout << "ValueProvider pitchWheelSensitivity " << value << "\n";
  return value;
}

Modulator::Modulator(const EntityMod::Modulator& configuration) noexcept :
configuration_{configuration},
amount_{configuration.amount()},
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
  }
}

std::string
Modulator::description() const noexcept
{
  std::ostringstream os;
  os << configuration().description();
  return os.str();
}

Float
Modulator::value(const State& state) const noexcept
{
  // If there is no source for the modulator, it always returns 0.0 (no modulation).
  if (!primaryValue_.isActive()) return 0_F;

  // Obtain transformed primary value.
  auto primary{primaryValue_(state)};
  Float transformedPrimary{primaryTransform_(primary)};
  if (transformedPrimary == 0_F) return 0_F;

  // Obtain transformed secondary value.
  Float transformedSecondary{secondaryValue_.isActive() ? secondaryTransform_(secondaryValue_(state)) : 1_F};
  Float result{transformedPrimary * transformedSecondary * amount_};
  // std::cout << "P: " << primary << " tP: " << transformedPrimary << " tS: " << transformedSecondary
  // << " amount: " << amount_ << " result: " << result << "\n";
  return result;
}
