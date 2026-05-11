// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Zone/Instrument.hpp"

using namespace SF2::Render::Zone;

Instrument::Instrument(GeneratorCollection&& gens, ModulatorCollection&& mods,
                       const IO::ChunkItems<Entity::SampleHeader>& sampleHeaders) noexcept :
Zone(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), Entity::Generator::Index::sampleID),
sampleHeader_{isGlobal() ? nullptr : &sampleHeaders[resourceLink()]}
{
  ;
}
