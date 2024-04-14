// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Instrument.hpp"

using namespace SF2::Render;

Instrument::Instrument(IO::File& file, const Entity::Instrument& config) noexcept :
WithCollectionBase<Zone::Instrument, Entity::Instrument>(config.zoneCount(), config) {
  for (const Entity::Bag& bag : file.instrumentZones().slice(config.firstZoneIndex(), config.zoneCount())) {
    zones_.add(Entity::Generator::Index::sampleID,
               file.instrumentZoneGenerators().slice(bag.firstGeneratorIndex(), bag.generatorCount()),
               file.instrumentZoneModulators().slice(bag.firstModulatorIndex(), bag.modulatorCount()),
               file.sampleSourceCollection());
  }
}

Instrument::CollectionType::Matches
Instrument::filter(int key, int velocity) const noexcept
{
  return zones_.filter(key, velocity);
}
