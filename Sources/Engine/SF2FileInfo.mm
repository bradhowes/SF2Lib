// Copyright © 2023 Brad Howes. All rights reserved.

#include "SF2FileInfo.hpp"
#include "SF2File/Entity/Preset.hpp"
#include "SF2File/IO/File.hpp"

SF2FileInfo::SF2FileInfo(std::string path)
: impl_{new SF2::IO::File()}, path_{path}
{}

bool
SF2FileInfo::load()
{
  // `File::load(int)` keeps its own duplicate of the descriptor, so ours is closed when `fd` goes out of scope.
  auto fd = SF2::IO::UniqueFd::openForReading(path_.c_str());
  return impl_->load(fd.get()) == SF2::IO::File::LoadResponse::ok;
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
