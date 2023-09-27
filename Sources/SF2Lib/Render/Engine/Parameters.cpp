#include <Foundation/Foundation.h>

#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/Parameters.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

inline static AUValue fromBool(bool value) noexcept { return value ? 1.0 : 0.0; }
inline static bool toBool(AUValue value) noexcept { return value >= 0.5; }

Parameters::Parameters(Engine& engine)
: engine_{engine}, parameterTree_{makeTree()}, log_{os_log_create("SF2Lib", "Parameters")}, anyChanged_{false}
{
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
Parameters::applyAll(SF2::Render::Voice::State::State& state) noexcept
{
  if (!anyChanged_) return;
  for (auto index : IndexIterator()) {
    if (changed_[index]) applyOne(state, index);
  }
}

void
Parameters::applyOne(SF2::Render::Voice::State::State& state, Index index) noexcept
{
  state.setValue(index, values_[index]);
}

void
Parameters::valueChanged(AUParameter* parameter, AUValue value) noexcept
{
  os_log_info(log_, "valueChanged - %llu %f", [parameter address], value);
  auto rawIndex = parameter.address;
  if (rawIndex < 0) return;
  if (rawIndex < valueOf(Index::numValues)) {
    auto index = Index(rawIndex);
    const auto& def = Definition::definition(index);
    values_[index] = def.clamp(int(std::round(value)));
    changed_[index] = true;
    anyChanged_ = true;
    engine_.notifyParameterChanged(index);
  } else if (rawIndex >= valueOf(EngineParameterAddress::portamentoModeEnabled) &&
             rawIndex < valueOf(EngineParameterAddress::firstUnusedAddress)) {
    auto address = EngineParameterAddress(rawIndex);
    switch (address) {
      case EngineParameterAddress::portamentoModeEnabled:
        engine_.setPortamentoModeEnabled(toBool(value));
        return;
      case EngineParameterAddress::portamentoRate:
        engine_.setPortamentoRate(size_t(value));
        return;
      case EngineParameterAddress::oneVoicePerKeyModeEnabled:
        engine_.setOneVoicePerKeyModeEnabled(toBool(value));
        return;
      case EngineParameterAddress::polyphonicModeEnabled:
        engine_.setPhonicMode(value >= 0.5 ? Engine::PhonicMode::poly : Engine::PhonicMode::mono);
        return;
      case EngineParameterAddress::activeVoiceCount:
        return;
      case EngineParameterAddress::retriggerModeEnabled:
        engine_.setRetriggerModeEnabled(toBool(value));
        return;
      case EngineParameterAddress::firstUnusedAddress:
        return;
    }
  }
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
      case EngineParameterAddress::portamentoModeEnabled:     return toBool(engine_.portamentoModeEnabled());
      case EngineParameterAddress::portamentoRate:            return engine_.portamentoRate();
      case EngineParameterAddress::oneVoicePerKeyModeEnabled: return toBool(engine_.oneVoicePerKeyModeEnabled());
      case EngineParameterAddress::polyphonicModeEnabled:     return toBool(engine_.polyphonicModeEnabled());
      case EngineParameterAddress::activeVoiceCount:          return engine_.activeVoiceCount();
      case EngineParameterAddress::retriggerModeEnabled:      return toBool(engine_.retriggerModeEnabled());
      case EngineParameterAddress::firstUnusedAddress:        return 0.0;
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
  NSMutableArray* definitions = [[NSMutableArray alloc] initWithCapacity:valueOf(Index::numValues)];

  for (auto index : IndexIterator()) {
    const auto& definition = Definition::definition(index);
    if (definition.valueKind() == Definition::ValueKind::UNUSED) {
      continue;
    }

    auto param = makeGeneratorParameter(index);
    [definitions addObject:param];
  }

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
