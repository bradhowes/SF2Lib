// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Entity/Bag.hpp"
#include "SF2Lib/Render/SampleSourceCollection.hpp"
#include "SF2Lib/Render/Zone/Zone.hpp"

namespace SF2::Render::Zone {

/**
 A specialization of a Zone for an Instrument. Non-global instrument zones must have a sample source which provides the
 raw samples used for rendering.
 */
class Instrument : public Zone {
public:

  /**
   Construct new instrument zone from entity in file.

   @param gens the vector of generators that define the zone
   @param mods the vector of modulators that define the zone
   @param sampleSources the samples for all of the instruments in the SF2 file
   */
  Instrument(GeneratorCollection&& gens, ModulatorCollection&& mods,
             const SampleSourceCollection& sampleSources) noexcept :
  Zone(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), Entity::Generator::Index::sampleID),
  sampleSource_{isGlobal() ? nullptr : &sampleSources[resourceLink()]}
  {}

  /// @returns the sample buffer registered to this zone. Throws exception if zone is global
  const Render::Voice::Sample::NormalizedSampleSource& sampleSource() const {
    if (sampleSource_ == nullptr) throw std::runtime_error("global instrument zone has no sample source");
    return *sampleSource_;
  }

  /**
   Apply the instrument zone to the given voice state. Sets the nominal value of the generators in the zone.

   @param state the voice state to update
   */
  void apply(Voice::State::State& state) const noexcept
  {
    // Generator state settings
    std::for_each(generators().cbegin(), generators().cend(), [&](const Entity::Generator::Generator& generator) {
      state.setValue(generator.index(), generator.value());
    });

    // Modulator definitions
    std::for_each(modulators().cbegin(), modulators().cend(), [&](const Entity::Modulator::Modulator& modulator) {
      state.addModulator(modulator);
    });
  }

private:
  const Render::Voice::Sample::NormalizedSampleSource* sampleSource_;
};

} // namespace SF2::Render
