// Copyright © 2023, 2026 Brad Howes. All rights reserved.

#pragma once

#include <string>
#include <swift/bridging>

namespace SF2 {
namespace Entity { class Preset; }
}

/**
 The name, bank and program of a preset in an SF2 file. Obtained from `SF2FileInfo`.
 */
struct SWIFT_ESCAPABLE SWIFT_SELF_CONTAINED SF2PresetInfo {
  SF2PresetInfo(std::string name, int bank, int program) : name_{name}, bank_{bank}, program_{program} {}

  /// @returns the name of the preset
  std::string name() const { return name_; }

  /// @returns the MIDI bank of the preset
  int bank() const noexcept { return bank_; }

  /// @returns the MIDI program of the preset
  int program() const noexcept { return program_; }

private:
  /// Construct from a preset entity. Private: `Entity::Preset` is not visible to Swift.
  SF2PresetInfo(const SF2::Entity::Preset& preset);

  std::string name_;
  int bank_;
  int program_;

  friend struct SF2FileInfo;
};
