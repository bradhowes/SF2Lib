// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "SF2File/IO/File.hpp"
#include "SF2Lib/Render/Preset.hpp"

using namespace SF2::Render;

Preset::Preset(IO::File& file, InstrumentCollection& instruments, const Entity::Preset& config) noexcept
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

bool
Preset::loadSamples(const IO::File &file) noexcept {
  // 32K seems to be a good value to use for speed.
  static constexpr size_t batchSampleCount = 32 * 1024;
  static constexpr Float normalizationScale = 1.0_F / Float(1 << 15);

  os_log_debug(log_, "loadSamples");

  auto pos = file.sampleDataBegin();
  assert(pos.available() >= 0);

  // Assume that samples for a preset will lie in the same general area of the samples chunk, so that we can simply identify the
  // min start and max end values and go. Alternate approach would be to take all of the start/end pairs, order by start, remove
  // duplicates, and then process each pair in turn. The first approach requires less book-keeping and is faster.
  size_t minStartIndex = size_t(pos.offset()) + size_t(pos.available());
  size_t maxEndIndex = 0;

  // Visit each preset zone.
  for (const auto& presetZone : zones()) {
    if (presetZone.isGlobal()) continue;
    const auto& instrument = presetZone.instrument();

    // Visit each instrument zone to get the instrument sample header.
    for (const auto& instrumentZone : instrument.zones()) {
      auto sampleHeader = instrumentZone.sampleHeader();
      if (sampleHeader == nullptr) continue;

      // Update the range of samples we will convert.
      if (sampleHeader->startIndex() < minStartIndex) minStartIndex = sampleHeader->startIndex();
      if (sampleHeader->endIndex() > maxEndIndex) maxEndIndex = sampleHeader->endIndex();
    }
  }

  os_log_debug(log_, "loadSamples - minStartIndex: %ld maxEndIndex %ld", minStartIndex, maxEndIndex);

  size_t remainingSamples = (maxEndIndex - minStartIndex) / sizeof(int16_t) + Zone::NormalizedSamples::sizePaddingAfterEnd;
  os_log_debug(log_, "loadSamples - remainingSamples: %ld", remainingSamples);

  normalizedSamples_.resize(remainingSamples);
  std::array<int16_t, batchSampleCount> rawSamples;

  auto ptr = normalizedSamples_.data();
  using elemType = std::remove_pointer_t<decltype(ptr)>;
  while (remainingSamples > 0) {
    auto sampleCount = std::min(remainingSamples, batchSampleCount);
    remainingSamples -= sampleCount;
    pos = pos.readInto(rawSamples.data(), sampleCount * sizeof(int16_t));

    // Convert from int16 to 32-bit float, saving into normalizedSamples via `ptr`.
    DSPHeaders::Accelerated<elemType>::conversionProc(rawSamples.data(), 1, ptr, 1, sampleCount);
    // Normalize 32-bit float values, converting in-place.
    DSPHeaders::Accelerated<elemType>::scaleProc(ptr, 1, &normalizationScale, ptr, 1, sampleCount);
    ptr += sampleCount;
  }

  assert(size_t(ptr - normalizedSamples_.data()) == normalizedSamples_.size());

  // Update all instrument zones to use the normalized samples.
  // Visit each preset zone.
  for (auto& presetZone : zones()) {
    if (presetZone.isGlobal()) continue;
    auto& instrument = presetZone.instrument();

    // Visit each instrument zone to get the instrument sample header.
    for (auto& instrumentZone : instrument.zones()) {
      auto sampleHeader = instrumentZone.sampleHeader();
      if (sampleHeader == nullptr) continue;
      instrumentZone.setNormalizedSamples(new Zone::NormalizedSamples(normalizedSamples_, minStartIndex, *sampleHeader));
    }
  }

  return true;
}

void
Preset::clearSamples() noexcept
{
  // Update all instrument zones to forget their normalized samples.
  for (auto& presetZone : zones()) {
    if (presetZone.isGlobal()) continue;
    auto& instrument = presetZone.instrument();
    for (auto& instrumentZone : instrument.zones()) {
      auto sampleHeader = instrumentZone.sampleHeader();
      if (sampleHeader == nullptr) continue;
      instrumentZone.setNormalizedSamples(nullptr);
    }
  }
}
