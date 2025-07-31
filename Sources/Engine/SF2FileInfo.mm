// Copyright © 2023 Brad Howes. All rights reserved.

#include "SF2FileInfo.hpp"
#include "SF2Lib/Entity/Preset.hpp"
#include "SF2Lib/IO/File.hpp"

SF2FileInfo::SF2FileInfo(const char* path)
: impl_{new SF2::IO::File(path)}
{}

SF2FileInfo::SF2FileInfo(std::string path)
: impl_{new SF2::IO::File(path)}
{}

SF2FileInfo::~SF2FileInfo() {}

bool
SF2FileInfo::load()
{
  if (impl_->load() != SF2::IO::File::LoadResponse::ok) return false;
  return true;
}

std::string SF2FileInfo::embeddedName() const noexcept { return impl_->embeddedName(); }
std::string SF2FileInfo::embeddedAuthor() const noexcept { return impl_->embeddedAuthor(); }
std::string SF2FileInfo::embeddedComment() const noexcept { return impl_->embeddedComment(); }
std::string SF2FileInfo::embeddedCopyright() const noexcept { return impl_->embeddedCopyright(); }

size_t
SF2FileInfo::size() const noexcept {
  return impl_->presets().size();
}

SF2PresetInfo
SF2FileInfo::operator[](size_t index) const noexcept {
  auto chunkIndex = impl_->presetIndicesOrderedByBankProgram()[index];
  auto preset = impl_->presets()[chunkIndex];
  return {preset};
}
