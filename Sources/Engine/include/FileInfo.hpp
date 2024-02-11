// Copyright © 2023 Brad Howes. All rights reserved.

#pragma once

#include <memory>
#include <Foundation/Foundation.h>
#include <CoreAudioKit/CoreAudioKit.h>
#include <string>
#include <swift/bridging>

namespace SF2 {

namespace Entity { class Preset; }
namespace IO { class File; }

/**
 Wrapper class for the SF2::Render::Engine that exposes a minimal API for Swift/C++ bridging. This perhaps better
 belongs in its own package.
 */
struct FileInfo
{
  explicit FileInfo(const char* path);
  explicit FileInfo(std::string path);

  struct PresetInfo {
    explicit PresetInfo(const Entity::Preset& presetf) noexcept;

    const std::string& name() const noexcept { return name_; }
    int bank() const noexcept { return bank_; }
    int program() const noexcept { return program_; }

  private:
    std::string name_;
    int bank_;
    int program_;
  };

  bool load();

  /// @returns the embedded name in the file
  const std::string& embeddedName() const noexcept;

  /// @returns the embedded author name in the file
  const std::string& embeddedAuthor() const noexcept;

  /// @returns any embedded comment in the file
  const std::string& embeddedComment() const noexcept;

  /// @returns any embedded copyright notice in the file
  const std::string& embeddedCopyright() const noexcept;

  const std::vector<PresetInfo> getPresets() const noexcept { return presets_; }

private:
  std::shared_ptr<IO::File> impl_;
  std::vector<PresetInfo> presets_;
};

} // SF2::DSP namespaces
