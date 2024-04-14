// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Preset.hpp"

using namespace SF2::Render;

Preset::Preset(IO::File& file, const InstrumentCollection& instruments, const Entity::Preset& config) noexcept
: WithCollectionBase<Zone::Preset, Entity::Preset>(config.zoneCount(), config)
{
  for (const Entity::Bag& bag : file.presetZones().slice(config.firstZoneIndex(), config.zoneCount())) {
    zones_.add(Entity::Generator::Index::instrument,
               file.presetZoneGenerators().slice(bag.firstGeneratorIndex(), bag.generatorCount()),
               file.presetZoneModulators().slice(bag.firstModulatorIndex(), bag.modulatorCount()),
               instruments);
  }
}

Preset::ConfigCollection
Preset::find(int key, int velocity) const noexcept
{
  ConfigCollection zonePairs;

  // Obtain the preset zones that match the key/velocity combination
  for (const Zone::Preset& preset : zones_.filter(key, velocity)) {

    // For each preset zone, scan to find an instrument to use for rendering
    const Instrument& presetInstrument = preset.instrument();
    auto globalInstrument = presetInstrument.globalZone();
    for (const Zone::Instrument& instrument : presetInstrument.filter(key, velocity)) {

      // Record a new Voice::Config with the preset/instrument zones to use for rendering
      zonePairs.emplace_back(preset, globalZone(), instrument, globalInstrument, key, velocity);
    }
  }

  return zonePairs;
}
