// Copyright © 2022 Brad Howes. All rights reserved.

#include <sstream>

#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render::Voice::State;

namespace EntityMod = Entity::Modulator;

int Modulator::ValueProvider::ccValue() const noexcept { return state_.channelState().continuousControllerValue(cc_); }
int Modulator::ValueProvider::noteOnKey() const noexcept { return state_.key(); }
int Modulator::ValueProvider::noteOnVelocity() const noexcept { return state_.velocity(); }
int Modulator::ValueProvider::keyPressure() const noexcept { return state_.channelState().notePressure(state_.key()); }
int Modulator::ValueProvider::channelPressure() const noexcept { return state_.channelState().channelPressure(); }
int Modulator::ValueProvider::pitchWheelValue() const noexcept { return state_.channelState().pitchWheelValue(); }
int Modulator::ValueProvider::pitchWheelSensitivity() const noexcept {
  return state_.channelState().pitchWheelSensitivity();
}

Modulator::Modulator(const EntityMod::Modulator& configuration, const State& state) noexcept :
configuration_{configuration},
amount_{configuration.amount()},
primaryValue_{makeValueProvider(configuration.source(), state)},
primaryTransform_{configuration.source()},
secondaryValue_{makeValueProvider(configuration.amountSource(), state)},
secondaryTransform_{configuration.amountSource()}
{}

Modulator::ValueProvider
Modulator::makeValueProvider(const EntityMod::Source& source, const State& state) noexcept
{
  using GI = EntityMod::Source::GeneralIndex;
  if (source.isContinuousController()) {
    int cc{source.ccIndex()};
    return ValueProvider{state, &ValueProvider::ccValue, cc};
  }
  switch (source.generalIndex()) {
    case GI::none: return ValueProvider{state};
    case GI::noteOnKey: return ValueProvider{state, &ValueProvider::noteOnKey};
    case GI::noteOnVelocity: return ValueProvider{state, &ValueProvider::noteOnVelocity};
    case GI::keyPressure: return ValueProvider{state, &ValueProvider::keyPressure};
    case GI::channelPressure: return ValueProvider{state, &ValueProvider::channelPressure};
    case GI::pitchWheel: return ValueProvider{state, &ValueProvider::pitchWheelValue};
    case GI::pitchWheelSensitivity: return ValueProvider{state, &ValueProvider::pitchWheelSensitivity};
  }
}

std::string
Modulator::description() const noexcept
{
  std::ostringstream os;
  os << configuration().description();
  return os.str();
}
