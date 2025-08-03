#include <Foundation/Foundation.h>

#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/Parameters.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;
using namespace SF2::Render::Voice::State;

Parameters::Parameters(Engine& engine)
: engine_{engine}
{
  makeTree();
  parameterTree_.implementorValueObserver = ^(AUParameter* parameter, AUValue value) { valueChanged(parameter, value); };
  parameterTree_.implementorValueProvider = ^(AUParameter* parameter) { return provideValue(parameter); };
}

void
Parameters::reset() noexcept
{
  os_log_info(log_, "reset");
  changed_.fill(false);
  anyChanged_ = false;
}

void
Parameters::applyChanged(State& state) noexcept
{
  auto anyChanged = anyChanged_.load();
  os_log_info(log_, "applyChanged - %d", anyChanged);
  if (!anyChanged) {
    return;
  }

  for (auto index : IndexIterator()) {
    if (changed_[index]) {
      applyOne(state, index);
    }
  }
}

void
Parameters::applyOne(State& state, Index index) noexcept
{
  os_log_info(log_, "applyOne - %lu %d", index, changed_[index]);
  state.setLiveValue(index, values_[index]);
}

void
Parameters::setLiveValue(Index index, AUValue value) noexcept
{
  const auto& def = Entity::Generator::Definition::definition(index);
  auto clamped = def.clamp(std::round(value));
  os_log_info(log_, "setLiveValue - index: %lu value: %f clamped: %f", index, value, clamped);
  values_[index] = clamped;
  changed_[index] = true;
  anyChanged_.store(true);
}

void
Parameters::valueChanged(AUParameter* parameter, AUValue value) noexcept
{
  os_log_info(log_, "valueChanged - %llu %s %f", parameter.address, parameter.identifier.UTF8String, value);
  auto rawIndex = parameter.address;
  if (rawIndex < 0) return;
  if (rawIndex < valueOf(Index::numValues)) {
    setLiveValue(Index(rawIndex), value);
  } else if (rawIndex >= valueOf(EngineParameterAddress::firstEngineParameterAddress) &&
             rawIndex < valueOf(EngineParameterAddress::lastEngineParameterAddressPlusOne)) {
    auto address = EngineParameterAddress(rawIndex);
    switch (address) {
      case EngineParameterAddress::portamentoModeEnabled:
        engine_.setPortamentoModeEnabled(SF2::toBool(value));
        break;
      case EngineParameterAddress::portamentoRate:
        engine_.setPortamentoRate(value);
        break;
      case EngineParameterAddress::oneVoicePerKeyModeEnabled:
        engine_.setOneVoicePerKeyModeEnabled(SF2::toBool(value));
        break;
      case EngineParameterAddress::polyphonicModeEnabled:
        engine_.setPhonicMode(SF2::toBool(value) ?
                              SF2::Render::Engine::Engine::PhonicMode::poly :
                              SF2::Render::Engine::Engine::PhonicMode::mono);
        break;
      case EngineParameterAddress::retriggerModeEnabled:
        engine_.setRetriggerModeEnabled(SF2::toBool(value));
        break;
      default: break;
    }
  }
}

AUValue
Parameters::provideValue(AUParameter* parameter) noexcept
{
  auto rawIndex = parameter.address;
  AUValue value;
  if (rawIndex < 0) {
    value = 0.0;
  }
  else if (rawIndex < valueOf(Index::numValues)) {
    auto index = Index(rawIndex);
    const auto& def = Definition::definition(index);
    value = def.clamp(values_[index]);
  } else if (rawIndex >= valueOf(EngineParameterAddress::firstEngineParameterAddress) &&
             rawIndex < valueOf(EngineParameterAddress::lastEngineParameterAddressPlusOne)) {
    auto address = EngineParameterAddress(rawIndex);
    switch (address) {
      case EngineParameterAddress::portamentoModeEnabled:
        value = SF2::fromBool(engine_.portamentoModeEnabled());
        break;
      case EngineParameterAddress::portamentoRate:
        value = engine_.portamentoRate();
        break;
      case EngineParameterAddress::oneVoicePerKeyModeEnabled:
        value = SF2::fromBool(engine_.oneVoicePerKeyModeEnabled());
        break;
      case EngineParameterAddress::polyphonicModeEnabled:
        value = SF2::fromBool(engine_.polyphonicModeEnabled());
        break;
      case EngineParameterAddress::activeVoiceCount:
        value = engine_.activeVoiceCount();
        break;
      case EngineParameterAddress::retriggerModeEnabled:
        value = SF2::fromBool(engine_.retriggerModeEnabled());
        break;
      case EngineParameterAddress::isRendering:
        value = SF2::fromBool(engine_.isRendering());
        break;
      case EngineParameterAddress::activeProgramIndex:
        value = engine_.activeProgramIndex();
        break;
      case EngineParameterAddress::activeBankIndex:
        value = engine_.activeBankIndex();
        break;
      case EngineParameterAddress::activePresetIndex:
        value = engine_.activePresetIndex();
        break;
      default: break;
    }
  }

  os_log_info(log_, "provideValue - %llu %s %f", parameter.address, parameter.identifier.UTF8String, value);
  return value;
}

AUParameter*
Parameters::makeGeneratorParameter(Index index) noexcept
{
  const auto& definition = Definition::definition(index);
  NSString* name = [NSString stringWithUTF8String:definition.name().data()];
  return [AUParameterTree createParameterWithIdentifier:name
                                                   name:name
                                                address:AUParameterAddress(valueOf(index))
                                                    min:AUValue(definition.valueRange().min)
                                                    max:AUValue(definition.valueRange().max)
                                                   unit:AudioUnitParameterUnit::kAudioUnitParameterUnit_Generic
                                               unitName:nullptr
                                                  flags:0
                                           valueStrings:nullptr
                                    dependentParameters:nullptr];
}

AUParameter*
Parameters::makeBooleanParameter(NSString* name, EngineParameterAddress address, bool value) noexcept
{
  auto flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
  auto param = [AUParameterTree createParameterWithIdentifier:name
                                                         name:name
                                                      address:valueOf(address)
                                                          min:0
                                                          max:1
                                                         unit:kAudioUnitParameterUnit_Boolean
                                                     unitName:nullptr
                                                        flags:flags
                                                 valueStrings:nullptr
                                          dependentParameters:nullptr];
  param.value = fromBool(value);
  return param;
}

void
Parameters::makeTree() noexcept
{
  os_log_info(log_, "makeTree");

  // This is a bit too large due to various unused generators found in the spec.
  auto capacity = NSUInteger(valueOf(Index::numValues) + engineParameterCount);
  auto definitions = [[NSMutableArray alloc] initWithCapacity:capacity];

  // Add definitions for all generators that are used by the SF2Lib engine
  for (auto index : IndexIterator()) {
    const auto& definition = Definition::definition(index);
    if (definition.valueKind() == Definition::ValueKind::UNUSED) {
      continue;
    }

    auto param = makeGeneratorParameter(index);
    [definitions addObject:param];
  }

  // Add definitions for the MIDI continuous controllers (CC) defined in the SF2 spec that can affect SF2Lib engine
  // rendering.
  [definitions addObject:makeBooleanParameter(@"portamentoModeEnabled",
                                              EngineParameterAddress::portamentoModeEnabled,
                                              engine_.portamentoModeEnabled())];
  [definitions addObject:makeBooleanParameter(@"oneVoicePerKeyModeEnabled",
                                              EngineParameterAddress::oneVoicePerKeyModeEnabled,
                                              engine_.oneVoicePerKeyModeEnabled())];
  [definitions addObject:makeBooleanParameter(@"polyphonicModeEnabled",
                                              EngineParameterAddress::polyphonicModeEnabled,
                                              engine_.polyphonicModeEnabled())];
  [definitions addObject:makeBooleanParameter(@"retriggerModeEnabled",
                                              EngineParameterAddress::retriggerModeEnabled,
                                              engine_.retriggerModeEnabled())];
  [definitions addObject:makeBooleanParameter(@"isRendering",
                                              EngineParameterAddress::isRendering,
                                              engine_.isRendering())];
  auto flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;
  auto param = [AUParameterTree createParameterWithIdentifier:@"portamentoRate"
                                                         name:@"portamentoRate"
                                                      address:valueOf(EngineParameterAddress::portamentoRate)
                                                          min:0
                                                          max:60000
                                                         unit:kAudioUnitParameterUnit_Milliseconds
                                                     unitName:nullptr
                                                        flags:flags
                                                 valueStrings:nullptr
                                          dependentParameters:nullptr];
  param.value = engine_.portamentoRate();
  [definitions addObject:param];

  flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_MeterReadOnly;
  [definitions addObject:[AUParameterTree createParameterWithIdentifier:@"activeVoiceCount"
                                                                   name:@"activeVoiceCount"
                                                                address:valueOf(EngineParameterAddress::activeVoiceCount)
                                                                    min:0
                                                                    max:engine_.voiceCount()
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];
  [definitions addObject:[AUParameterTree createParameterWithIdentifier:@"activeProgramIndex"
                                                                   name:@"activeProgramIndex"
                                                                address:valueOf(EngineParameterAddress::activeProgramIndex)
                                                                    min:0
                                                                    max:127
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];
  [definitions addObject:[AUParameterTree createParameterWithIdentifier:@"activeBankIndex"
                                                                   name:@"activeBankIndex"
                                                                address:valueOf(EngineParameterAddress::activeBankIndex)
                                                                    min:0
                                                                    max:127
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];
  [definitions addObject:[AUParameterTree createParameterWithIdentifier:@"activePresetIndex"
                                                                   name:@"activePresetIndex"
                                                                address:valueOf(EngineParameterAddress::activePresetIndex)
                                                                    min:0
                                                                    max:65535
                                                                   unit:kAudioUnitParameterUnit_Generic
                                                               unitName:nullptr
                                                                  flags:flags
                                                           valueStrings:nullptr
                                                    dependentParameters:nullptr]];
  parameterTree_ = [AUParameterTree createTreeWithChildren:definitions];
}
