// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <atomic>
#include <memory>

#include "SF2Lib/Render/PresetCollection.hpp"

namespace SF2::Render::Engine {

struct PresetsState {
  PresetsState() noexcept = default;

  PresetsState(int fd, size_t index, PresetsState* past) noexcept
  : file_{std::make_unique<IO::File>()}, past_{past} {
    initialize(file_->load(fd), index);
  }

  PresetsState(const std::string& path, size_t index, PresetsState* past) noexcept
  : file_{std::make_unique<IO::File>(path)}, past_{past} {
    initialize(file_->load(), index);
  }

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

  inline bool hasActivePreset() const noexcept { return activePresetIndex_.load() < size(); }

  inline size_t size() const noexcept { return collection_.size(); }

  inline Preset& activePreset() {
    auto activePresetIndex = activePresetIndex_.load();
    if (activePresetIndex >= size()) throw std::runtime_error("unexpected nil active preset");
    return collection_[activePresetIndex];
  }

  void deletePast() noexcept {
    if (past_) {
      delete past_;
      past_ = nullptr;
    }
  }

  inline size_t activePresetIndex() const noexcept { return activePresetIndex_.load(); }

  inline IO::File::LoadResponse loadResponse() const noexcept { return loadResponse_; }

  inline size_t locatePresetIndex(uint16_t bank, uint8_t program) const noexcept {
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
  PresetsState* past_{nullptr};
  IO::File::LoadResponse loadResponse_{IO::File::LoadResponse::none};
};

} // end namespace SF2::Render::Engine
