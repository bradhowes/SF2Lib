// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>
// #include <limits>

#include "SF2Lib/Render/Zone/Preset.hpp"

using namespace SF2::Render::Zone;

Preset::Preset(GeneratorCollection&& gens, ModulatorCollection&& mods,
               const Render::InstrumentCollection& instruments) noexcept :
Zone(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), Entity::Generator::Index::instrument),
instrument_{isGlobal() ? nullptr : &instruments[resourceLink()]}
{}

const SF2::Render::Instrument&
Preset::instrument() const
{
  if (instrument_ == nullptr) throw std::runtime_error("global preset zone has no instrument");
  return *instrument_;
}
