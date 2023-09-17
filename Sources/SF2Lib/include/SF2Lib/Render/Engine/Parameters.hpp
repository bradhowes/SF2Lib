// Copyright © 2023 Brad Howes. All rights reserved.

#pragma once

#include <CoreAudioKit/CoreAudioKit.h>
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render::Engine {

class Engine;

class Parameters
{
public:
  Parameters(Engine& engine);

  void reset() noexcept;
  
  void apply(SF2::Render::Voice::State::State& state) noexcept;

  void setValue(AUParameter* parameter, AUValue value) noexcept;

  AUValue getValue(AUParameter* parameter) noexcept;

  static AUParameter* makeParameter(SF2::Entity::Generator::Index index) noexcept;

  static AUParameterTree* makeTree() noexcept;

private:
  Engine& engine_;
  AUParameterTree* parameterTree_{nullptr};
  Entity::Generator::GeneratorValueArray<int> values_{};
  Entity::Generator::GeneratorValueArray<bool> changed_{};
  bool anyChanged_;
};

}
