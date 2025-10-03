#pragma once

#include <string>
#include <swift/bridging>

namespace SF2 {
namespace Entity { class Preset; }
}

struct SWIFT_ESCAPABLE SF2PresetInfo {

  SF2PresetInfo(std::string name, int bank, int program) : name_{name}, bank_{bank}, program_{program} {}

  SF2PresetInfo(const SF2::Entity::Preset& preset);

  std::string name() const noexcept { return name_; }

  int bank() const noexcept { return bank_; }

  int program() const noexcept { return program_; }

private:
  std::string name_;
  int bank_;
  int program_;
};
