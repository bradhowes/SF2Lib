// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <vector>

#include "SF2Lib/Render/Preset.hpp"

namespace SF2::IO { class File; }
namespace SF2::Render {

/**
 Collection of all of the `Entity::Preset` instances in an SF2 file, each of which is wrapped in a `Render::Preset` instance for
 use during audio rendering.

 Note that the collection is used by the real-time rendering thread while there are active voices.

 After loading from an SF2 file, no `Render::Preset` instances have any samples -- they are generated on-demand so as to minimize
 memory pressure on mobile devices.
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

  /**
   Remove existing entries from the container, retaining capacity of the container.

   NOTE: there should be **no** active voices when invoked. Otherwise, there is a risk rendering artifacts or worse, a crash.
   */
  void clear() noexcept;

  /// @returns true if the collection is empty. Thread-safe.
  inline bool empty() const noexcept { return size_.load() == 0; }

  /// @returns the number of presets in the collection. Thread-safe.
  inline size_t size() const noexcept { return size_.load(); }

  /// @returns the preset at a given index.
  Preset& operator[](size_t index) noexcept { return checkedVectorIndexing(presets_, index); }

  /// @returns the preset at a given index.
  const Preset& operator[](size_t index) const noexcept { return checkedVectorIndexing(presets_, index); }

  /**
   Locate the index of the preset based on bank/program pair.

   @param bank the bank to locate
   @param program the program in the bank to locate
   @returns index of the `Preset` if found or `size()` if not. The caller must validate before passing to `operator[]`.
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
  InstrumentCollection instruments_{};
  std::atomic<size_t> size_{0};
};

} // namespace SF2::Render
