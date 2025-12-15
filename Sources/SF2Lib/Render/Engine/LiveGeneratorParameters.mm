#include <Foundation/Foundation.h>

#include "SF2File/Entity/Generator/Definition.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/LiveGeneratorParameters.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;
using namespace SF2::Render::Voice::State;

void
LiveGeneratorParameters::reset() noexcept
{
  os_log_info(log_, "reset");
  isChanged_.fill(false);
  anyChanged_ = false;
}

void
LiveGeneratorParameters::applyChanged(State& state) noexcept
{
  os_log_info(log_, "applyChanged - %d", anyChanged_);
  if (!anyChanged_) {
    return;
  }

  for (auto index : IndexIterator()) {
    if (isChanged_[index]) {
      applyOneGenerator(state, index);
    }
  }
}

void
LiveGeneratorParameters::setLiveValue(Index index, AUValue value) noexcept
{
  const auto& def = Entity::Generator::Definition::definition(index);
  auto clamped = def.clamp(std::round(value));
  os_log_info(log_, "setLiveValue - index: %lu value: %f clamped: %f", index, value, clamped);
  liveValues_[index] = int(clamped);
  isChanged_[index] = true;
  anyChanged_ = true;
}
