// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "DSPHeaders/Accelerated.hpp"

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

  // Visit the preset zones that match the key/velocity combination. Visiting (rather than `filter`, which builds a
  // vector) keeps this free of allocations, since it runs on the render thread for every note-on.
  zones_.visit(key, velocity, [&](const Zone::Preset& preset) {

    // For each preset zone, scan to find an instrument to use for rendering
    const Instrument& presetInstrument = preset.instrument();
    auto globalInstrument = presetInstrument.globalZone();
    presetInstrument.zones().visit(key, velocity, [&](const Zone::Instrument& instrument) {

      // Record a new Voice::Config with the preset/instrument zones to use for rendering
      if (!zonePairs.emplace_back(preset, globalZone(), instrument, globalInstrument, key, velocity)) {
        os_log_error(log_, "find - more than %zu zones match key %d velocity %d; ignoring the rest",
                     maxConfigsPerNote, key, velocity);
      }
    });
  });

  return zonePairs;
}

bool
Preset::loadSamples(const IO::File &file) noexcept {
  // 32K seems to be a good value to use for speed.
  static constexpr size_t batchSampleCount = 32 * 1024;
  static constexpr Float normalizationScale = 1.0_F / Float(1 << 15);
  static constexpr size_t padding = Zone::NormalizedSampleSpan::sizePaddingAfterEnd;

  os_log_info(log_, "loadSamples - %s", configuration().name().c_str());

  /// A run of the `smpl` chunk to load: file sample indices [fileStart, fileEnd), stored from `bufferStart` onwards.
  struct Run {
    size_t fileStart;
    size_t fileEnd;
    size_t bufferStart;
  };

  // Load only the samples that the preset's instrument zones use: each header's samples plus the 46 that follow it
  // (SF2.01 7.10). Loading everything between the lowest start and the highest end used to hold most of the file for
  // presets whose samples are spread out, such as drum kits. Overlapping or touching runs are merged. Samples are
  // usually stored one after another with their 46 padding samples in between, so a typical preset is still one run.
  // This runs on the work queue, so the temporary vector is fine.
  std::vector<Run> runs;
  try {
    for (const auto& presetZone : zones()) {
      if (presetZone.isGlobal()) continue;
      for (const auto& instrumentZone : presetZone.instrument().zones()) {
        auto sampleHeader = instrumentZone.sampleHeader();
        if (sampleHeader == nullptr) continue;
        runs.emplace_back(sampleHeader->startIndex(), sampleHeader->endIndex() + padding, 0);
      }
    }
  } catch (const std::bad_alloc&) {
    os_log_error(log_, "loadSamples - out of memory for %{public}s", configuration().name().c_str());
    normalizedSamples_.clear();
    return false;
  }

  // A preset whose zones reference no samples has nothing to load.
  if (runs.empty()) {
    normalizedSamples_.clear();
    return true;
  }

  // Sort the runs by the fileStart value. Look for overlaps and consolidate any. Should be left with the minimum number of
  // runs necessary to hold the samples of the preset.
  std::sort(runs.begin(), runs.end(), [](const Run& lhs, const Run& rhs) { return lhs.fileStart < rhs.fileStart; });
  size_t merged = 0;
  for (size_t index = 1; index < runs.size(); ++index) {
    if (runs[index].fileStart <= runs[merged].fileEnd) {
      runs[merged].fileEnd = std::max(runs[merged].fileEnd, runs[index].fileEnd);
    } else {
      runs[++merged] = runs[index];
    }
  }

  // Drop off runs that have been merged.
  runs.resize(merged + 1);

  // Update each run with the offset to use for the first sample.
  size_t totalSampleCount = 0;
  for (auto& run : runs) {
    run.bufferStart = totalSampleCount;
    totalSampleCount += run.fileEnd - run.fileStart;
  }

  os_log_info(log_, "loadSamples - runs: %ld samples: %ld", runs.size(), totalSampleCount);

  std::array<int16_t, batchSampleCount> rawSamples;
  using elemType = SampleVector::value_type;
  auto chunkBegin = file.sampleDataBegin();
  assert(chunkBegin.available() >= 0);
  auto chunkSampleCount = size_t(chunkBegin.available()) / sizeof(int16_t);
  try {

    // Now build the collection of samples from the runs.
    normalizedSamples_.assign(totalSampleCount, 0_F);
    for (const auto& run : runs) {
      // `File::validate` guarantees that every sample header lies inside the `smpl` chunk, but the padding after the
      // last one may not, so stop at the end of the chunk and leave the rest as zeros.
      if (run.fileStart >= chunkSampleCount) continue;
      auto remainingSampleCount = std::min(run.fileEnd, chunkSampleCount) - run.fileStart;
      auto pos = chunkBegin.advance(off_t(run.fileStart * sizeof(int16_t)));
      auto ptr = normalizedSamples_.data() + run.bufferStart;
      while (remainingSampleCount > 0) {
        auto sampleCount = std::min(remainingSampleCount, batchSampleCount);
        remainingSampleCount -= sampleCount;
        pos = pos.readInto(rawSamples.data(), sampleCount * sizeof(int16_t));
        DSPHeaders::Accelerated<elemType>::conversionProc(rawSamples.data(), 1, ptr, 1, sampleCount);
        DSPHeaders::Accelerated<elemType>::scaleProc(ptr, 1, &normalizationScale, ptr, 1, sampleCount);
        ptr += sampleCount;
      }
    }
  } catch (IO::File::LoadResponse) {
    os_log_error(log_, "loadSamples - failed to read samples for %{public}s", configuration().name().c_str());
    normalizedSamples_.clear();
    return false;
  } catch (const std::bad_alloc&) {
    os_log_error(log_, "loadSamples - out of memory for %{public}s", configuration().name().c_str());
    normalizedSamples_.clear();
    return false;
  }

  // Update all instrument zones to use spans of normalized samples. Each header lies inside exactly one merged run: the
  // last one that starts at or before it.
  for (auto& presetZone : zones()) {
    if (presetZone.isGlobal()) continue;
    auto& instrument = presetZone.instrument();
    for (auto& instrumentZone : instrument.zones()) {
      auto sampleHeader = instrumentZone.sampleHeader();
      if (sampleHeader == nullptr) continue;
      auto start = sampleHeader->startIndex();
      auto run = std::prev(std::upper_bound(runs.begin(), runs.end(), start, [](size_t value, const Run& run) {
        return value < run.fileStart;
      }));
      auto firstIndex = run->bufferStart + (start - run->fileStart);
      instrumentZone.setSamples(std::make_shared<Zone::NormalizedSampleSpan>(normalizedSamples_, firstIndex, *sampleHeader));
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
