#include <Foundation/Foundation.h>

#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/Parameters.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;
using namespace SF2::Render::Voice::State;

Parameters::Parameters(Engine& engine)
: engine_{engine}, parameterTree_{makeTree()}, log_{os_log_create("SF2Lib", "Parameters")}, anyChanged_{false}
{
  //NOTE: this is *not* for the real-time rendering thread. It should only be used to convey changes to a UI.
  parameterTree_.implementorValueObserver = ^(AUParameter* parameter, AUValue value) { valueChanged(parameter, value); };
  parameterTree_.implementorValueProvider = ^(AUParameter* parameter) { return provideValue(parameter); };
}

void
Parameters::reset() noexcept
{
  changed_.fill(false);
  anyChanged_ = false;
}

void
Parameters::applyChanged(State& state) noexcept
{
  if (!anyChanged_) return;
  for (auto index : IndexIterator()) {
    if (changed_[index]) applyOne(state, index);
  }
}

void
Parameters::applyOne(State& state, Index index) noexcept
{
  state.setLiveValue(index, values_[index]);
}

void
Parameters::setLiveValue(Index index, int value) noexcept
{
  values_[index] = value;
  changed_[index] = true;
  anyChanged_ = true;
}

void
Parameters::valueChanged(AUParameter* parameter, AUValue value) noexcept
{
  os_log_info(log_, "valueChanged - %llu %f", [parameter address], value);
}

AUValue
Parameters::provideValue(AUParameter* parameter) noexcept
{
  os_log_info(log_, "provideValue - %llu", [parameter address]);
  auto rawIndex = parameter.address;
  if (rawIndex < 0) return 0.0;
  if (rawIndex < valueOf(Index::numValues)) {
    auto index = Index(rawIndex);
    const auto& def = Definition::definition(index);
    return def.clamp(values_[Index(rawIndex)]);
  } else if (rawIndex >= valueOf(EngineParameterAddress::portamentoModeEnabled) &&
             rawIndex < valueOf(EngineParameterAddress::firstUnusedAddress)) {
    auto address = EngineParameterAddress(rawIndex);
    switch (address) {
      case EngineParameterAddress::portamentoModeEnabled:     return SF2::toBool(engine_.portamentoModeEnabled());
      case EngineParameterAddress::portamentoRate:            return engine_.portamentoRate();
      case EngineParameterAddress::oneVoicePerKeyModeEnabled: return SF2::toBool(engine_.oneVoicePerKeyModeEnabled());
      case EngineParameterAddress::polyphonicModeEnabled:     return SF2::toBool(engine_.polyphonicModeEnabled());
      case EngineParameterAddress::activeVoiceCount:          return engine_.activeVoiceCount();
      case EngineParameterAddress::retriggerModeEnabled:      return SF2::toBool(engine_.retriggerModeEnabled());
      case EngineParameterAddress::firstUnusedAddress:        return 0.0;
      default: return 0.0;
    }
  } else {
    return 0.0;
  }
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

AUParameterTree*
Parameters::makeTree() noexcept
{
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
  return [AUParameterTree createTreeWithChildren:definitions];
}
