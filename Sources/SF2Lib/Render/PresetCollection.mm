// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#include <cmath>

#include "SF2File/IO/File.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"

using namespace SF2::Render;

void
PresetCollection::build(SF2::IO::File& file)
{
  clear();
  instruments_.build(file);

  auto& presetConfigs{file.presets()};
  auto count = presetConfigs.size();
  if (presets_.capacity() < count) presets_.reserve(count);

  // Build the collection of Preset instances so that they are ordered by their underlying config's bank/program
  // numbers.
  for (auto presetIndex : file.presetIndicesOrderedByBankProgram()) {
    presets_.emplace_back(file, instruments_, presetConfigs[presetIndex]);
  }

  // At this point, the collection is safe to use from render thread.
  size_.store(presets_.size());
}

void
PresetCollection::clear() noexcept
{
  // Prevent future use of this container from the render thread until it has been rebuilt via `build(file)`
  size_.store(0);
  presets_.clear();
  instruments_.clear();
}

size_t
PresetCollection::locatePresetIndex(uint16_t bank, uint16_t program) const noexcept
{
  if (size_.load() == 0) {
    return 0;
  }

  // Search for the first entry that is not less than the value being searched for (uses binary search).
  Entity::Preset config{bank, program};
  auto found = std::lower_bound(presets_.begin(), presets_.end(), config,
                                [](const Preset& preset, const Entity::Preset& key) {
    return preset.configuration() < key;
  });

  if (found == presets_.end() || found->configuration() != config) return presets_.size();
  ssize_t offset = std::distance(presets_.begin(), found);
  if (offset < 0) offset = -offset;

  return static_cast<size_t>(offset);
}

const Preset*
PresetCollection::locatePreset(uint16_t bank, uint16_t program) const noexcept
{
  auto index = locatePresetIndex(bank, program);
  return index == size() ? nullptr : &presets_[index];
}
