// Copyright © 2022 Brad Howes. All rights reserved.

#include <limits>

#include "SF2Lib/Render/Zone/Instrument.hpp"

using namespace SF2::Render::Zone;

Instrument::Instrument(GeneratorCollection&& gens, ModulatorCollection&& mods,
                       const SampleSourceCollection& sampleSources) noexcept :
Zone(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), Entity::Generator::Index::sampleID),
sampleSource_{isGlobal() ? nullptr : &sampleSources[resourceLink()]}
{
  ;
}

const SF2::Render::Voice::Sample::NormalizedSampleSource&
Instrument::sampleSource() const
{
  if (sampleSource_ == nullptr) throw std::runtime_error("global instrument zone has no sample source");
  return *sampleSource_;
}

void
Instrument::apply(Voice::State::State& state) const noexcept
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
