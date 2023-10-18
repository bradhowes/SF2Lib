// Copyright © 2023 Brad Howes. All rights reserved.

#pragma once

#include <CoreAudioKit/CoreAudioKit.h>

#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render::Engine {

class Engine;

/**
 Collection of AUParameter definitions which are used to generate an AUParameterTree for controlling SF2 generates
 while rendering.
 */
class Parameters
{
public:
  using Index = Entity::Generator::Index;
  using State = Voice::State::State;

  enum struct EngineParameterAddress : AUParameterAddress
  {
    portamentoModeEnabled = 1000,
    portamentoRate,
    oneVoicePerKeyModeEnabled,
    polyphonicModeEnabled,
    activeVoiceCount,
    retriggerModeEnabled,
    firstUnusedAddress
  };

  /**
   Construct new instance for the given Engine

   @param engine the Engine to operate on
   */
  Parameters(Engine& engine);

  /**
   Clear the state such that there are no differences from the active preset generators.
   */
  void reset() noexcept;

  /**
   Set a parameter value due to an AUParameterTree entry change. Note that this is called from the real-time
   render thread.

   @param index the index of the generator that is being changed
   @param value the new value for the generator
   */
  void setLiveValue(Index index, int value) noexcept;

  /**
   Apply any changed values to the given voice state.

   @param state the state to update
   */
  void applyChanged(State& state) noexcept;

  /**
   Apply one changed value to the given voice state.

   @param state the state to update
   @param index the generator to update
   */
  void applyOne(State& state, Index index) noexcept;

  /// @returns the AUParameterTree defined for the engine
  AUParameterTree* parameterTree() const noexcept { return parameterTree_; }

private:

  /**
   Notification that the given AUParameter has a new value.

   @param parameter the parameter that changed
   @param value the new value
   */
  void valueChanged(AUParameter* parameter, AUValue value) noexcept;

  /**
   Obtain the current value of a generator.

   @param parameter the AUParameter to query
   @returns the current value
   */
  AUValue provideValue(AUParameter* parameter) noexcept;

  static AUParameter* makeGeneratorParameter(Index index) noexcept;

  static AUParameter* makeBooleanParameter(NSString* name, EngineParameterAddress, bool value) noexcept;

  AUParameterTree* makeTree() noexcept;

  Engine& engine_;
  AUParameterTree* parameterTree_{nullptr};
  Entity::Generator::GeneratorValueArray<int> values_{};
  Entity::Generator::GeneratorValueArray<bool> changed_{};
  os_log_t log_;
  bool anyChanged_;
};

}
