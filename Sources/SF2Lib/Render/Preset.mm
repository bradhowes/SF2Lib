// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "SF2File/IO/File.hpp"
#include "SF2Lib/Render/Preset.hpp"

using namespace SF2::Render;

Preset::Preset(IO::File& file, InstrumentCollection& instruments, const Entity::Preset& config) noexcept :
WithCollectionBase<Zone::Preset, Entity::Preset>(config.zoneCount(), config)
{
  for (const Entity::Bag& bag : file.presetZones().slice(config.firstZoneIndex(), config.zoneCount())) {
    zones_.add(Entity::Generator::Index::instrument,
               file.presetZoneGenerators().slice(bag.firstGeneratorIndex(), bag.generatorCount()),
               file.presetZoneModulators().slice(bag.firstModulatorIndex(), bag.modulatorCount()),
               instruments);
  }
  os_log_debug(log_, "Preset - %s", configuration().name().c_str());
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

  os_log_debug(log_, "loadSamples - %s", configuration().name().c_str());

  auto pos = file.sampleDataBegin();
  assert(pos.available() >= 0);

  // Assume that samples for a preset will lie in the same general area of the samples chunk, so that we can simply identify the
  // min start and max end values and go. Alternate approach would be to take all of the start/end pairs, order by start, remove
  // duplicates, and then process each pair in turn. The first approach requires less book-keeping and should be marginally faster.
  // The risk is that there are holes in the spans and the underlying `normalizedSamples_` container is too large.

  size_t minStartIndex = size_t(pos.offset()) + size_t(pos.available());
  size_t maxEndIndex = 0;

  // Visit each preset zone.
  for (const auto& presetZone : zones()) {
    if (presetZone.isGlobal()) continue;
    const auto& instrument = presetZone.instrument();

    // Visit each instrument zone to get the instrument's sample header bounds.
    for (const auto& instrumentZone : instrument.zones()) {
      auto sampleHeader = instrumentZone.sampleHeader();
      if (sampleHeader == nullptr) continue;
      // Update the range of samples we will convert.
      minStartIndex = std::min(sampleHeader->startIndex(), minStartIndex);
      maxEndIndex = std::max(sampleHeader->endIndex(), maxEndIndex);
    }
  }

  os_log_debug(log_, "loadSamples - minStartIndex: %ld maxEndIndex %ld", minStartIndex, maxEndIndex);

  size_t remainingSampleCount = (maxEndIndex - minStartIndex) + Zone::NormalizedSampleSpan::sizePaddingAfterEnd + 1;
  os_log_debug(log_, "loadSamples - remainingSampleCount: %ld", remainingSampleCount);

  normalizedSamples_.resize(remainingSampleCount);
  std::array<int16_t, batchSampleCount> rawSamples;

  // Point to the first 16-bit sample associated with this preset, and copy over remainingSampleCount 16-bit samples in
  // batchSampleCount chunks.
  pos = pos.advance(minStartIndex * sizeof(int16_t));
  auto ptr = normalizedSamples_.data();
  using elemType = std::remove_pointer_t<decltype(ptr)>;
  while (remainingSampleCount > 0) {
    auto sampleCount = std::min(remainingSampleCount, batchSampleCount);
    remainingSampleCount -= sampleCount;
    pos = pos.readInto(rawSamples.data(), sampleCount * sizeof(int16_t));
    DSPHeaders::Accelerated<elemType>::conversionProc(rawSamples.data(), 1, ptr, 1, sampleCount);
    DSPHeaders::Accelerated<elemType>::scaleProc(ptr, 1, &normalizationScale, ptr, 1, sampleCount);
    ptr += sampleCount;
  }

  // Update all instrument zones to use spans of normalized samples.
  for (auto& presetZone : zones()) {
    if (presetZone.isGlobal()) continue;
    auto& instrument = presetZone.instrument();
    for (auto& instrumentZone : instrument.zones()) {
      auto sampleHeader = instrumentZone.sampleHeader();
      if (sampleHeader == nullptr) continue;
      instrumentZone.setSamples(std::make_shared<Zone::NormalizedSampleSpan>(normalizedSamples_, minStartIndex, *sampleHeader));
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
      instrumentZone.releaseSamples();
    }
  }
  normalizedSamples_.clear();
}
