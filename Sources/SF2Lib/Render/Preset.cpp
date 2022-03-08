// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Preset.hpp"

using namespace SF2::Render;

Preset::Preset(const IO::File& file, const InstrumentCollection& instruments, const Entity::Preset& config) noexcept
: Zone::WithCollectionBase<Zone::Preset, Entity::Preset>(config.zoneCount(), config)
{
  for (const Entity::Bag& bag : file.presetZones().slice(config.firstZoneIndex(), config.zoneCount())) {
    zones_.add(Entity::Generator::Index::instrument,
               file.presetZoneGenerators().slice(bag.firstGeneratorIndex(), bag.generatorCount()),
               file.presetZoneModulators().slice(bag.firstModulatorIndex(), bag.modulatorCount()),
               instruments);
  }
}
