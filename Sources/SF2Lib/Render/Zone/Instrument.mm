// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Zone/Instrument.hpp"

using namespace SF2::Render::Zone;

Instrument::Instrument(GeneratorCollection &&gens, ModulatorCollection &&mods,
                       const IO::SampleSourceCollection &sampleSources) noexcept
: Zone(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), Entity::Generator::Index::sampleID),
sampleHeader_{isGlobal() ? nullptr : &sampleSources[resourceLink()].header()},
sampleSource_{isGlobal() ? nullptr : &sampleSources[resourceLink()]}
{
  ;
}

Instrument::Instrument(GeneratorCollection&& gens, ModulatorCollection&& mods,
                       const IO::ChunkItems<Entity::SampleHeader>& sampleHeaders) noexcept :
Zone(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), Entity::Generator::Index::sampleID),
sampleHeader_{isGlobal() ? nullptr : &sampleHeaders[resourceLink()]}
{
  ;
}

const SF2::IO::NormalizedSampleSource&
Instrument::sampleSource() const
{
  if (sampleSource_ == nullptr) throw std::runtime_error("global instrument zone has no sample source");
  return *sampleSource_;
}

const NormalizedSamples&
Instrument::samples() const
{
  if (samples_.get() == nullptr) throw std::runtime_error("global instrument zone has no sample source");
  return *samples_;
}
