// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"

using namespace SF2::Render;

void
PresetCollection::build(const SF2::IO::File& file)
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
}

void
PresetCollection::clear() noexcept
{
  presets_.clear();
  instruments_.clear();
}

const Preset&
PresetCollection::operator[](size_t index) const noexcept
{
  return checkedVectorIndexing(presets_, index);
}

size_t
PresetCollection::locatePresetIndex(uint16_t bank, uint16_t program) const noexcept
{

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
