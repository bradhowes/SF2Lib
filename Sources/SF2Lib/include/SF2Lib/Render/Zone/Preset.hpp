// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Entity/Bag.hpp"
#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/InstrumentCollection.hpp"
#include "SF2Lib/Render/Zone/Zone.hpp"

namespace SF2::Render::Zone {

/**
 A specialization of a Zone for a Preset. Non-global Preset zones must refer to an Instrument.
 */
class Preset : public Zone {
public:

  /**
   Construct new preset zone from entity in file.

   @param gens the vector of generators that define the zone
   @param mods the vector of modulators that define the zone
   @param instruments collection of instrument definitions found in the file
   */
  Preset(GeneratorCollection&& gens, ModulatorCollection&& mods,
         const Render::InstrumentCollection& instruments) noexcept :
  Zone(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), Entity::Generator::Index::instrument),
  instrument_{isGlobal() ? nullptr : &instruments[resourceLink()]}
  {}

  /// @returns the Instrument configured for this zone. Throws exception if zone is global.
  const Render::Instrument& instrument() const {
    if (instrument_ == nullptr) throw std::runtime_error("global preset zone has no instrument");
    return *instrument_;
  }

  /**
   Apply the zone to the given voice state by adjusting the nominal value of the generators in the zone.

   @param state the voice state to update
   */
  void refine(Voice::State::State& state) const noexcept
  {
    std::for_each(generators().cbegin(), generators().cend(), [&](const Entity::Generator::Generator& generator) {
      if (generator.definition().isAvailableInPreset()) {
        state.setAdjustment(generator.index(), generator.value());
      }
    });
  }

private:
  const Render::Instrument* instrument_;
};

} // namespace SF2::Render
