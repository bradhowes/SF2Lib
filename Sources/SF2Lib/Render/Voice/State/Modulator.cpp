// Copyright © 2022 Brad Howes. All rights reserved.

#include <sstream>

#include "SF2Lib/Entity/Modulator/Modulator.hpp"
#include "SF2Lib/Entity/Modulator/Source.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render::Voice::State;

namespace EntityMod = Entity::Modulator;

int Modulator::ValueProvider::ccValue() const noexcept { return state_.channelState().continuousControllerValue(cc_); }
int Modulator::ValueProvider::key() const noexcept { return state_.key(); }
int Modulator::ValueProvider::velocity() const noexcept { return state_.velocity(); }
int Modulator::ValueProvider::keyPressure() const noexcept { return state_.channelState().keyPressure(state_.key()); }
int Modulator::ValueProvider::channelPressure() const noexcept { return state_.channelState().channelPressure(); }
int Modulator::ValueProvider::pitchWheelValue() const noexcept { return state_.channelState().pitchWheelValue(); }
int Modulator::ValueProvider::pitchWheelSensitivity() const noexcept {
  return state_.channelState().pitchWheelSensitivity();
}
int Modulator::ValueProvider::linked() const noexcept { return std::round(modulator_->value()); };

Modulator::Modulator(size_t index, const EntityMod::Modulator& configuration, const State& state) noexcept :
configuration_{configuration},
index_{index},
amount_{configuration.amount()},
sourceTransform_{configuration.source()},
amountTransform_{configuration.amountSource()},
sourceValue_{makeValueProvider(configuration.source(), state)},
amountScale_{makeValueProvider(configuration.amountSource(), state)}
{
  log_.debug() << "adding " << index << ' ' << configuration.description() << std::endl;
}

void
Modulator::setSource(const Modulator& modulator) noexcept
{
  sourceValue_.modulator_ = &modulator;
  sourceValue_.proc_ = &ValueProvider::linked;
}

Modulator::ValueProvider
Modulator::makeValueProvider(const EntityMod::Source& source, const State& state) noexcept
{
  using GI = EntityMod::Source::GeneralIndex;
  if (source.isContinuousController()) {
    int cc{source.continuousIndex()};
    return ValueProvider{state, &ValueProvider::ccValue, cc};
  }
  switch (source.generalIndex()) {
    case GI::none: return ValueProvider{state};
    case GI::noteOnKeyValue: return ValueProvider{state, &ValueProvider::key};
    case GI::noteOnVelocity: return ValueProvider{state, &ValueProvider::velocity};
    case GI::keyPressure: return ValueProvider{state, &ValueProvider::keyPressure};
    case GI::channelPressure: return ValueProvider{state, &ValueProvider::channelPressure};
    case GI::pitchWheel: return ValueProvider{state, &ValueProvider::pitchWheelValue};
    case GI::pitchWheelSensitivity: return ValueProvider{state, &ValueProvider::pitchWheelSensitivity};
    case GI::link: return ValueProvider{state};
  }
}

std::string
Modulator::description() const noexcept
{
  std::ostringstream os;
  os << configuration().description();
  return os.str();
}
