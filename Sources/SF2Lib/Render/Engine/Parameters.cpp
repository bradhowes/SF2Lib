#include <Foundation/Foundation.h>

#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/Parameters.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

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
  if (rawIndex < 0 || rawIndex >= valueOf(Index::numValues)) return;
  auto index = Index(rawIndex);
  const auto& def = Definition::definition(index);
  values_[index] = def.clamp(int(std::round(value)));
  changed_[index] = true;
  anyChanged_ = true;
  engine_.notifyParameterChanged(index);
}

AUValue
Parameters::getValue(AUParameter* parameter) noexcept
{
  auto rawIndex = parameter.address;
  if (rawIndex < 0 || rawIndex >= valueOf(Index::numValues)) return 0.0;
  auto index = Index(rawIndex);
  const auto& def = Definition::definition(index);
  return def.clamp(values_[Index(rawIndex)]);
}

AUParameter*
Parameters::makeParameter(Index index) noexcept
{
  const auto& definition = Definition::definition(index);
  assert(definition.valueKind() != Definition::ValueKind::UNUSED);

  NSString* name = [NSString stringWithCString:definition.name().data() encoding:kUnicodeUTF8Format];

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

AUParameterTree*
Parameters::makeTree() noexcept
{
  NSMutableArray* definitions = [[NSMutableArray alloc] initWithCapacity:valueOf(Index::numValues)];

  for (auto index : IndexIterator()) {
    const auto& definition = Definition::definition(index);
    if (definition.valueKind() == Definition::ValueKind::UNUSED) {
      continue;
    }

    auto param = makeParameter(index);
    assert(param != nullptr);

    [definitions addObject:param];
  }

  return [AUParameterTree createTreeWithChildren:definitions];
}
