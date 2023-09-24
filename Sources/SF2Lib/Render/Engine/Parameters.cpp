#include <Foundation/Foundation.h>

#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/Parameters.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

enum struct EngineParameterAddress : AUParameterAddress
{
  portamentoEnabled = 1000,
  portamentoRate = 1001,
  oneVoicePerKey = 1002,
  polyphonicEnabled = 1003,
};

Parameters::Parameters(Engine& engine)
: engine_{engine}, parameterTree_{makeTree()}, anyChanged_{false}
{
  parameterTree_.implementorValueObserver = ^(AUParameter* parameter, AUValue value) { setValue(parameter, value); };
  parameterTree_.implementorValueProvider = ^(AUParameter* parameter) { return getValue(parameter); };
}

void
Parameters::reset() noexcept
{
  changed_.fill(false);
  anyChanged_ = false;
}

void
Parameters::applyAll(SF2::Render::Voice::State::State& state) noexcept
{
  if (!anyChanged_) return;

  for (auto index : IndexIterator()) {
    if (changed_[index]) {
      state.setValue(index, values_[index]);
    }
  }
}

void
Parameters::applyOne(SF2::Render::Voice::State::State& state, Index index) noexcept
{
  state.setValue(index, values_[index]);
}

void
Parameters::setValue(AUParameter* parameter, AUValue value) noexcept
{
  auto rawIndex = parameter.address;
  if (rawIndex < 0) return;
  if (rawIndex < valueOf(Index::numValues)) {
    auto index = Index(rawIndex);
    const auto& def = Definition::definition(index);
    values_[index] = def.clamp(int(std::round(value)));
    changed_[index] = true;
    anyChanged_ = true;
    engine_.notifyParameterChanged(index);
  } else if (rawIndex >= valueOf(EngineParameterAddress::portamentoEnabled) &&
             rawIndex <= valueOf(EngineParameterAddress::polyphonicEnabled)) {
    auto address = EngineParameterAddress(rawIndex);
    switch (address) {
      case EngineParameterAddress::portamentoEnabled:
        engine_.channelState().setPortamentoEnabled(value >= 0.5 ? true : false);
        return;
      case EngineParameterAddress::portamentoRate:
        engine_.channelState().setPortamentoRate(size_t(value));
        return;
      case EngineParameterAddress::oneVoicePerKey:
        engine_.channelState().setOneVoicePerKey(value >= 0.5 ? true : false);
        return;
      case EngineParameterAddress::polyphonicEnabled:
        engine_.channelState().setPhonicMode(value >= 0.5 ? 
                                             MIDI::ChannelState::PhonicMode::poly :
                                             MIDI::ChannelState::PhonicMode::mono);
        return;
    }
  }
}

AUValue
Parameters::getValue(AUParameter* parameter) noexcept
{
  auto rawIndex = parameter.address;
  if (rawIndex < 0) return 0.0;
  if (rawIndex < valueOf(Index::numValues)) {
    auto index = Index(rawIndex);
    const auto& def = Definition::definition(index);
    return def.clamp(values_[Index(rawIndex)]);
  } else if (rawIndex >= valueOf(EngineParameterAddress::portamentoEnabled) &&
             rawIndex <= valueOf(EngineParameterAddress::polyphonicEnabled)) {
    auto address = EngineParameterAddress(rawIndex);
    switch (address) {
      case EngineParameterAddress::portamentoEnabled:
        return engine_.channelState().portamentoEnabled();
      case EngineParameterAddress::portamentoRate:
        return engine_.channelState().portamentoRate();
      case EngineParameterAddress::oneVoicePerKey:
        return engine_.channelState().oneVoicePerKey();
      case EngineParameterAddress::polyphonicEnabled:
        return engine_.channelState().polyphonicMode();
    }
  } else {
    return 0.0;
  }
}

AUParameter*
Parameters::makeGeneratorParameter(Index index) noexcept
{
  const auto& definition = Definition::definition(index);
  assert(definition.valueKind() != Definition::ValueKind::UNUSED);

  NSString* name = [NSString stringWithUTF8String:definition.name().data()];

  auto param = [AUParameterTree createParameterWithIdentifier:name
                                                         name:name
                                                      address:AUParameterAddress(valueOf(index))
                                                          min:AUValue(definition.valueRange().min)
                                                          max:AUValue(definition.valueRange().max)
                                                         unit:AudioUnitParameterUnit::kAudioUnitParameterUnit_Generic
                                                     unitName:nullptr
                                                        flags:0
                                                 valueStrings:nullptr
                                          dependentParameters:nullptr];
  return param;
}

AUParameter*
Parameters::makeBooleanParameter(NSString* name, AUParameterAddress address) noexcept
{
  return [AUParameterTree createParameterWithIdentifier:name
                                                   name:name
                                                address:address
                                                    min:0
                                                    max:1
                                                   unit:kAudioUnitParameterUnit_Boolean
                                               unitName:nullptr
                                                  flags:0
                                           valueStrings:nullptr
                                    dependentParameters:nullptr];
}

AUParameterTree*
Parameters::makeTree() noexcept
{
  NSMutableArray* definitions = [[NSMutableArray alloc] initWithCapacity:valueOf(Index::numValues)];

  for (auto index : IndexIterator()) {
    const auto& definition = Definition::definition(index);
    if (definition.valueKind() == Definition::ValueKind::UNUSED) {
      continue;
    }

    auto param = makeGeneratorParameter(index);
    assert(param != nullptr);

    [definitions addObject:param];
  }

  [definitions addObject:makeBooleanParameter(@"portamentoEnabled", valueOf(EngineParameterAddress::portamentoEnabled))];
  [definitions addObject:makeBooleanParameter(@"oneVoicePerKey", valueOf(EngineParameterAddress::oneVoicePerKey))];
  [definitions addObject:makeBooleanParameter(@"polyphonicEnabled", valueOf(EngineParameterAddress::polyphonicEnabled))];
  [definitions addObject:[AUParameterTree createParameterWithIdentifier:@"portamentoRate"
                                                                   name:@"portamentoRate"
                                                                address:valueOf(EngineParameterAddress::portamentoRate)
                                                                    min:0
                                                                    max:60000
                                                                   unit:kAudioUnitParameterUnit_Milliseconds
                                                               unitName:nullptr
                                                                  flags:0
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];
  return [AUParameterTree createTreeWithChildren:definitions];
}
