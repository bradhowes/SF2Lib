// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <map>
#include <vector>

#include "SF2Lib/Render/Preset.hpp"

namespace SF2::IO { class File; }
namespace SF2::Render {

/**
 Collection of all of the Entity::Preset instances in an SF2 file, each of which is wrapped in a
 Render::Preset instance for use during audio rendering.
 */
class PresetCollection
{
public:

  PresetCollection() = default;

  /**
   Build a collection using the contents of the given file

   @param file the data to use to build the preset collection
   */
  void build(const IO::File& file)
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

  void clear() noexcept
  {
    presets_.clear();
    instruments_.clear();
  }

  /// @returns the number of presets in the collection.
  size_t size() const noexcept { return presets_.size(); }

  /// @returns the preset at a given index.
  const Preset& operator[](size_t index) const noexcept { return checkedVectorIndexing(presets_, index); }

  /**
   Locate the index of the preset based on bank/program pair.

   @param bank the bank to locate
   @param program the program in the bank to locate
   @returns index of the `Preset` if found or `size()`
   */
  size_t locatePresetIndex(uint16_t bank, uint16_t program) const noexcept {

    // Search for the first entry that is not less than the value being searched for (uses binary search).
    Entity::Preset config{bank, program};
    auto found = std::lower_bound(presets_.begin(), presets_.end(), config,
                                  [](const Preset& preset, const Entity::Preset& config) {
      return preset.configuration() < config;
    });

    if (found == presets_.end() || found->configuration() != config) return presets_.size();
    ssize_t offset = std::distance(presets_.begin(), found);
    if (offset < 0) offset = -offset;

    return static_cast<size_t>(offset);
  }

  /**
   Locate a preset based on bank/program pair.

   @param bank the bank to locate
   @param program the program in the bank to locate
   @returns pointer to `Preset` if found or nullptr if not found
   */
  const Preset* locatePreset(uint16_t bank, uint16_t program) const noexcept {
    auto index = locatePresetIndex(bank, program);
    return index == size() ? nullptr : &presets_[index];
  }

private:
  std::vector<Preset> presets_{};
  InstrumentCollection instruments_;
};

} // namespace SF2::Render
