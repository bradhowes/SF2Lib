// Copyright © 2022 Brad Howes. All rights reserved.

#include <sstream>

#include "Entity/Modulator/Modulator.hpp"
#include "Entity/Modulator/Source.hpp"
#include "MIDI/Channel.hpp"
#include "Render/Voice/State/Modulator.hpp"
#include "Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render::Voice::State;

namespace EntityMod = Entity::Modulator;

int Modulator::ValueProvider::ccValue() const { return state_.channel().continuousControllerValue(cc_); }
int Modulator::ValueProvider::key() const { return state_.key(); }
int Modulator::ValueProvider::velocity() const { return state_.velocity(); }
int Modulator::ValueProvider::keyPressure() const { return state_.channel().keyPressure(state_.key()); }
int Modulator::ValueProvider::channelPressure() const { return state_.channel().channelPressure(); }
int Modulator::ValueProvider::pitchWheelValue() const { return state_.channel().pitchWheelValue(); }
int Modulator::ValueProvider::pitchWheelSensitivity() const { return state_.channel().pitchWheelSensitivity(); }
int Modulator::ValueProvider::linked() const { return std::round(modulator_->value()); };

Modulator::Modulator(size_t index, const EntityMod::Modulator& configuration, const State& state) :
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
Modulator::setSource(const Modulator& modulator)
{
  sourceValue_.modulator_ = &modulator;
  sourceValue_.proc_ = &ValueProvider::linked;
}

Modulator::ValueProvider
Modulator::makeValueProvider(const EntityMod::Source& source, const State& state)
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
Modulator::description() const
{
  std::ostringstream os;
  os << configuration().description();
  return os.str();
}
