// Copyright © 2023, 2026 Brad Howes. All rights reserved.

#pragma once

#include <atomic>

#include <CoreAudioKit/CoreAudioKit.h>

#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render::Engine {

/**
 Collection of AUParameter definitions which are used to generate an AUParameterTree for controlling SF2 generators
 while rendering. There are two sets of parameters: global settings for the engine, and settings that affect the state
 of a voice/instrument that is rendering audio. The parameter ID for the global settings are found in the
 `EngineParameterAddress` enum, while the SF2 generator parameter IDs match those of the SF2 generator enum found in
 `SF2::Entity::Generator`.
 */
class LiveGeneratorParameters
{
public:
  using Index = Entity::Generator::Index;
  using State = Voice::State::State;

  /**
   Clear the state such that there are no differences from the active preset generators.
   */
  void reset() noexcept;

  /**
   Apply any changed values to the given voice state.

   @param state the state to update
   */
  void applyChanged(State& state) noexcept;

  /**
   Set a parameter value due to an AUParameterTree entry change. Note that this is called from the real-time
   render thread.

   @param index the index of the generator that is being changed
   @param value the new value for the generator
   */
  void setLiveValue(Index index, AUValue value) noexcept;

  /**
   Obtain the current value of a generator.

   @param index the index of the generator
   @returns the current value
   */
  inline AUValue getLiveValue(Index index) const noexcept { return AUValue(liveValues_[index]); }

  /**
   Apply one changed value to the given voice state.

   @param state the state to update
   @param index the generator to update
   */
  inline void applyOneGenerator(State& state, Index index) noexcept {
    state.setLiveValue(index, liveValues_[index]);
  }

private:
  // Current "live" generator settings
  Entity::Generator::GeneratorValueArray<int> liveValues_{};
  // Indicator that value was changed by external source since last check.
  Entity::Generator::GeneratorValueArray<bool> isChanged_{};
  // Indicator that there is at least one changed generator value.
  bool anyChanged_{false};

  const os_log_t log_{Log::create("Parameters")};
};

}
