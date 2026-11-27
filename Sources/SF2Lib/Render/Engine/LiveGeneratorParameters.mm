#include <Foundation/Foundation.h>

#include "SF2File/Entity/Generator/Definition.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/LiveGeneratorParameters.hpp"
#include "SF2Lib/Render/LowPassFilter.hpp"

using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;
using namespace SF2::Render::Voice::State;

void
LiveGeneratorParameters::reset() noexcept
{
  os_log_debug(log_, "reset");
  isChanged_.fill(false);
  anyChanged_ = false;
}

void
LiveGeneratorParameters::applyChanged(State& state) noexcept
{
  os_log_debug(log_, "applyChanged - %d", anyChanged_);
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
  auto clamped = liveValueRange(index).clamp(std::round(value));
  os_log_debug(log_, "setLiveValue - index: %lu value: %f clamped: %f", index, value, clamped);
  liveValues_[index] = int(clamped);
  isChanged_[index] = true;
  anyChanged_ = true;
}

Definition::ValueRange
LiveGeneratorParameters::liveValueRange(Index index) noexcept
{
  const auto& range = Definition::definition(index).valueRange();
  switch (index) {
    case Index::delayModulatorEnvelope:
    case Index::attackModulatorEnvelope:
    case Index::delayVolumeEnvelope:
    case Index::attackVolumeEnvelope:
      return {-32'768, range.max};
    case Index::initialFilterCutoff:
      return {range.min, int(SF2::Render::LowPassFilter::bypassFrequency)};
    default:
      return range;
  }
}
