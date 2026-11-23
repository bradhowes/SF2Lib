// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <atomic>
#include <memory>

#include "SF2Lib/Render/PresetCollection.hpp"

namespace SF2::Render::Engine {

/**
 The presets of one loaded SF2 file. A new instance is created for every file load. The Engine publishes it to the
 render thread and frees it off the render thread once the render thread has moved on to a newer one (see
 `Engine::installPresetsState_WQ` and `Engine::syncPresetsState_RT`). Instances are never shared between loads, so a
 voice can never outlive the samples it is playing.
 */
struct PresetsState {
  /**
   Load presets from a file descriptor.

   @param fd the descriptor to read from (duplicated by `IO::File`)
   @param index the preset to make active
   @param generation the sequence number of this load. Generations increase with every load.
   */
  PresetsState(int fd, size_t index, uint64_t generation)
  : file_{std::make_unique<IO::File>()}, generation_{generation} {
    initialize(file_->load(fd), index);
  }

  /**
   Load presets from a file path.

   @param path the path of the file to load
   @param index the preset to make active
   @param generation the sequence number of this load. Generations increase with every load.
   */
  PresetsState(const std::string& path, size_t index, uint64_t generation)
  : file_{std::make_unique<IO::File>(path)}, generation_{generation} {
    initialize(file_->load(), index);
  }

  /// @returns the sequence number of the load that created this instance
  uint64_t generation() const noexcept { return generation_; }

  void changeActivePreset(size_t index) noexcept {
    auto activePresetIndex = activePresetIndex_.load();
    if (activePresetIndex < size()) {
      collection_[activePresetIndex].clearSamples();
    }
    activePresetIndex = std::min(index, size());
    if (activePresetIndex < size()) {
      if (!collection_[activePresetIndex].loadSamples(*file_)) {
        activePresetIndex = size();
      }
    }
    activePresetIndex_.store(activePresetIndex);
  }

  bool hasActivePreset() const noexcept { return activePresetIndex_.load() < size(); }

  size_t size() const noexcept { return collection_.size(); }

  /// @returns the active preset, or nullptr if there is none. Does not throw, so it is safe on the render thread.
  Preset* activePresetOrNull() noexcept {
    auto activePresetIndex = activePresetIndex_.load();
    return activePresetIndex < size() ? &collection_[activePresetIndex] : nullptr;
  }

  Preset& activePreset() {
    auto activePresetIndex = activePresetIndex_.load();
    if (activePresetIndex >= size()) throw std::runtime_error("unexpected nil active preset");
    return collection_[activePresetIndex];
  }

  size_t activePresetIndex() const noexcept { return activePresetIndex_.load(); }

  IO::File::LoadResponse loadResponse() const noexcept { return loadResponse_; }

  size_t locatePresetIndex(uint16_t bank, uint8_t program) const noexcept {
    return collection_.locatePresetIndex(bank, program);
  }

private:
  PresetsState(const PresetsState&) = delete;
  PresetsState(PresetsState&&) = delete;

  void initialize(IO::File::LoadResponse loadResponse, size_t index) {
    loadResponse_ = loadResponse;
    if (loadResponse == IO::File::LoadResponse::ok) {
      collection_.build(*file_);
    } else {
      collection_.clear();
    }
    activePresetIndex_.store(std::min(index, size()));
  }

  std::unique_ptr<IO::File> file_{};
  PresetCollection collection_{};
  std::atomic<size_t> activePresetIndex_{0};
  uint64_t generation_{0};
  IO::File::LoadResponse loadResponse_{IO::File::LoadResponse::none};
};

} // end namespace SF2::Render::Engine
