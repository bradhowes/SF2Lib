// Copyright © 2023, 2026 Brad Howes. All rights reserved.

#include "SF2FileInfo.hpp"
#include "SF2File/Entity/Preset.hpp"
#include "SF2File/IO/File.hpp"

SF2FileInfo::SF2FileInfo(std::string path)
: impl_{new SF2::IO::File()}, path_{path}
{}

// Defined here, where `File` is complete (the header only forward-declares it).
SF2FileInfo::SF2FileInfo(SF2FileInfo&&) = default;
SF2FileInfo& SF2FileInfo::operator=(SF2FileInfo&&) = default;
SF2FileInfo::~SF2FileInfo() = default;

SF2::IO::LoadResponse
SF2FileInfo::load()
{
  // `File::load(int)` keeps its own duplicate of the descriptor, so ours is closed when `fd` goes out of scope.
  auto fd = SF2::IO::UniqueFd::openForReading(path_.c_str());
  if (!fd.isValid()) return SF2::IO::LoadResponse::notFound;
  return impl_->load(fd.get());
}

std::string SF2FileInfo::embeddedName() const { return impl_->embeddedName(); }
std::string SF2FileInfo::embeddedAuthor() const { return impl_->embeddedAuthor(); }
std::string SF2FileInfo::embeddedComment() const { return impl_->embeddedComment(); }
std::string SF2FileInfo::embeddedCopyright() const { return impl_->embeddedCopyright(); }

size_t
SF2FileInfo::size() const noexcept {
  return impl_->presets().size();
}

std::optional<SF2PresetInfo>
SF2FileInfo::operator[](size_t index) const {
  const auto& ordered = impl_->presetIndicesOrderedByBankProgram();
  if (index >= size() || index >= ordered.size()) return std::nullopt;
  return SF2PresetInfo(impl_->presets()[ordered[index]]);
}
