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
   Apply any changed values to the given voice state.

   @param state the state to update
   */
  void applyAll(SF2::Render::Voice::State::State& state) noexcept;

  /**
   Apply one changed value to the given voice state.

   @param state the state to update
   @param index the generator to update
   */
  void applyOne(SF2::Render::Voice::State::State& state, Entity::Generator::Index index) noexcept;

  /**
   Notification that the given AUParameter has a new value

   @param parameter the parameter that changed
   @param value the new value
   */
  void setValue(AUParameter* parameter, AUValue value) noexcept;

  /**
   Obtain the current value of a generator.

   @param parameter the AUParameter to query
   @returns the current value
   */
  AUValue getValue(AUParameter* parameter) noexcept;

  /**
   Create a new AUParameter definition for a generator.

   @param index the index of the generator to use
   @returns new AUParameter instance
   */
  static AUParameter* makeParameter(Entity::Generator::Index index) noexcept;

  /**
   Create a AUParameterTree containing the AUParameter instances for the generators.

   @returns the AUParameterTree with all of the generator children
   */
  static AUParameterTree* makeTree() noexcept;

private:
  Engine& engine_;
  AUParameterTree* parameterTree_{nullptr};
  Entity::Generator::GeneratorValueArray<int> values_{};
  Entity::Generator::GeneratorValueArray<bool> changed_{};
  bool anyChanged_;
};

}
