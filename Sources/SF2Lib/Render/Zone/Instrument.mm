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
