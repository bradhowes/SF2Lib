// Copyright © 2022 Brad Howes. All rights reserved.

#include <limits>

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

/**
 Apply the zone to the given voice state by adjusting the nominal value of the generators in the zone.

 @param state the voice state to update
 */
void
Preset::refine(Voice::State::State& state) const noexcept
{
  const auto& gens{generators()};
  std::for_each(gens.cbegin(), gens.cend(), [&](const Entity::Generator::Generator& generator) {
    if (generator.definition().isAvailableInPreset()) {
      state.setAdjustment(generator.index(), generator.value());
    }
  });
}
