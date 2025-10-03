#pragma once

#include <memory>
#include <string>
#include <swift/bridging>

#include "SF2PresetInfo.hpp"

namespace SF2 {
namespace IO { class File; }
}

/**
 A light-weight SF2 loader that provides meta data and preset information. It does not load samples nor does it
 create the render entities such as the preset and instrument zones.
 */
struct SWIFT_ESCAPABLE SF2FileInfo
{
  // SF2FileInfo(const char* path);

  SF2FileInfo(std::string path);

  ~SF2FileInfo();

  bool load();

  /// @returns the embedded name in the file
  std::string embeddedName() const noexcept;

  /// @returns the embedded author name in the file
  std::string embeddedAuthor() const noexcept;

  /// @returns any embedded comment in the file
  std::string embeddedComment() const noexcept;

  /// @returns any embedded copyright notice in the file
  std::string embeddedCopyright() const noexcept;

  size_t size() const noexcept;

  SF2PresetInfo operator[](size_t index) const noexcept;

private:
  std::shared_ptr<SF2::IO::File> impl_;
};
