// Copyright © 2023, 2026 Brad Howes. All rights reserved.

#pragma once

#include <atomic>

#include <CoreAudioKit/CoreAudioKit.h>

#include "SF2File/Entity/Generator/Definition.hpp"
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
  AUValue getLiveValue(Index index) const noexcept { return AUValue(liveValues_[index]); }

  /**
   Obtain the range of values accepted for a generator from the AUParameterTree. This is the generator's range from the
   spec, except where the engine gives meaning to a value outside it:

   - the LFO delays and the delay, attack and hold of the volume and modulation envelopes (SF2.01 8.1.2 #21, #23,
     #25-#27, #33-#35) may be -32768, which the spec says "conventionally indicates" no delay, an instantaneous attack
     or no hold phase. The LFOs and envelopes take it as no time at all, instead of the 1 ms of the spec's -12000
     lower bound (see `DSP::lfoDelayTimecentsToSeconds` and `Envelope::Generator`).
   - initialFilterCutoff (#8) may reach `LowPassFilter::bypassFrequency`, where a filter without resonance does not
     affect the signal; the spec's 13500 upper bound is just below it

   @param index the index of the generator
   @returns the range of accepted values
   */
  static Entity::Generator::Definition::ValueRange liveValueRange(Index index) noexcept;

  /**
   Apply one changed value to the given voice state.

   @param state the state to update
   @param index the generator to update
   */
  void applyOneGenerator(State& state, Index index) noexcept {
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
