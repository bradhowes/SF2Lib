// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <map>
#include <vector>

#include "SF2Lib/Render/Preset.hpp"

namespace SF2::IO { class File; }
namespace SF2::Render::Engine {

/**
 Collection of all of the Entity::Preset instances in an SF2 file, each of which is wrapped in a
 Render::Preset instance for use during audio rendering.
 */
class PresetCollection
{
public:

  /**
   Representation of a key for a preset that is made up of the bank and program values used to call it up. The
   collection will store the presets in increasing order based on these values.
   */
  struct BankProgram
  {
    int bank;
    int program;

    friend bool operator ==(const BankProgram& lhs, const BankProgram& rhs) noexcept {
      return lhs.bank == rhs.bank && lhs.program == rhs.program;
    }

    friend bool operator <(const BankProgram& lhs, const BankProgram& rhs) noexcept {
      return lhs.bank < rhs.bank || (lhs.bank == rhs.bank && lhs.program < rhs.program);
    }
  };

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

    // The order of the presets from the file is unknown. We could order them by first-come, but here we visit each one
    // and map their bank/program numbers to their arrival read index. Then we iterate over the map and create Preset
    // entries that are sorted by increasing bank and program number.
    for (size_t index = 0; index < count; ++index) {
      auto& config{presetConfigs[index]};
      BankProgram key{config.bank(), config.program()};
      std::cout << index << ' ' << key.bank << '/' << key.program << ' ' << presetConfigs[index].name() << '\n';
      auto [_, success] = ordering_.insert({key, index});
      if (!success) throw std::runtime_error("duplicate bank/program pair");
      presets_.emplace_back(file, instruments_, presetConfigs[index]);
    }
  }

  void clear() noexcept
  {
    presets_.clear();
    ordering_.clear();
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
  size_t locatePresetIndex(int bank, int program) const noexcept {
    const auto& pos{ordering_.find({bank, program})};
    std::cout << bank << '/' << program << '=' << pos->second << '\n';
    return pos == ordering_.end() ? size() : pos->second;
  }

  /**
   Locate a preset based on bank/program pair.

   @param bank the bank to locate
   @param program the program in the bank to locate
   @returns pointer to `Preset` if found or nullptr if not found
   */
  const Preset* locatePreset(int bank, int program) const noexcept {
    auto index = locatePresetIndex(bank, program);
    return index == size() ? nullptr : &presets_[index];
  }

private:
  std::vector<Preset> presets_{};
  std::map<BankProgram, size_t> ordering_{};
  InstrumentCollection instruments_;
};

} // namespace SF2::Render
