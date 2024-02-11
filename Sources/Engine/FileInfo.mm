// Copyright © 2023 Brad Howes. All rights reserved.

#include "FileInfo.hpp"
#include "SF2Lib/Entity/Preset.hpp"
#include "SF2Lib/IO/File.hpp"

SF2::FileInfo::PresetInfo::PresetInfo(const SF2::Entity::Preset& preset) noexcept
: name_{preset.name()}, bank_{preset.bank()}, program_{preset.program()}
{}

SF2::FileInfo::FileInfo(const char* path)
: impl_{new SF2::IO::File(path)}
{}

SF2::FileInfo::FileInfo(std::string path)
: impl_{new SF2::IO::File(path)}
{}

bool
SF2::FileInfo::load()
{
  if (impl_->load() != IO::File::LoadResponse::ok) return false;
  presets_.reserve(impl_->presetIndicesOrderedByBankProgram().size());
  for (auto index : impl_->presetIndicesOrderedByBankProgram()) {
    presets_.emplace_back(impl_->presets()[index]);
  }
  return true;
}

const std::string& SF2::FileInfo::embeddedName() const noexcept { return impl_->embeddedName(); }
const std::string& SF2::FileInfo::embeddedAuthor() const noexcept { return impl_->embeddedAuthor(); }
const std::string& SF2::FileInfo::embeddedComment() const noexcept { return impl_->embeddedComment(); }
const std::string& SF2::FileInfo::embeddedCopyright() const noexcept { return impl_->embeddedCopyright(); }
