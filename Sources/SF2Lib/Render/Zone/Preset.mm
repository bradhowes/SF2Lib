// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Zone/Preset.hpp"

using namespace SF2::Render::Zone;

Preset::Preset(GeneratorCollection &&gens, ModulatorCollection &&mods,
               Render::InstrumentCollection &instruments) noexcept :
Zone(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), Entity::Generator::Index::instrument),
instrument_{isGlobal() ? nullptr : &instruments[resourceLink()]}
{}
