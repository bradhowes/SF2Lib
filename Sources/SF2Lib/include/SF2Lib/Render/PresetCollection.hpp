// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

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
  void build(IO::File& file);

  void clear() noexcept;

  bool empty() const noexcept { return presets_.empty(); }

  /// @returns the number of presets in the collection.
  size_t size() const noexcept { return presets_.size(); }

  /// @returns the preset at a given index.
  const Preset& operator[](size_t index) const noexcept;

  /**
   Locate the index of the preset based on bank/program pair.

   @param bank the bank to locate
   @param program the program in the bank to locate
   @returns index of the `Preset` if found or `size()`
   */
  size_t locatePresetIndex(uint16_t bank, uint16_t program) const noexcept;

  /**
   Locate a preset based on bank/program pair.

   @param bank the bank to locate
   @param program the program in the bank to locate
   @returns pointer to `Preset` if found or nullptr if not found
   */
  const Preset* locatePreset(uint16_t bank, uint16_t program) const noexcept;

private:
  std::vector<Preset> presets_{};
  InstrumentCollection instruments_;
};

} // namespace SF2::Render
