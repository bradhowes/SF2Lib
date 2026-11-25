// Copyright © 2023, 2026 Brad Howes. All rights reserved.

#pragma once

#include <memory>
#include <optional>
#include <string>
#include <swift/bridging>

#include "SF2File/IO/LoadResponse.hpp"
#include "SF2PresetInfo.hpp"

namespace SF2 {
namespace IO { class File; }
}

/**
 A light-weight SF2 loader that provides meta data and preset information. It does not load samples nor does it
 create the render entities such as the preset and instrument zones.

 An SF2FileInfo owns its parsed file, so it cannot be copied, only moved. Swift imports it as a non-copyable
 (`~Copyable`) type.
 */
struct SWIFT_ESCAPABLE SWIFT_SELF_CONTAINED SF2FileInfo
{
  /**
   Construct new instance with the contents from the given file.

   @param path the location of the file to load
   */
  SF2FileInfo(std::string path);

  SF2FileInfo(const SF2FileInfo&) = delete;
  SF2FileInfo& operator=(const SF2FileInfo&) = delete;
  SF2FileInfo(SF2FileInfo&&);
  SF2FileInfo& operator=(SF2FileInfo&&);
  ~SF2FileInfo();

  /**
   Attempt to load the file pointed to in the constructor.

   @returns `LoadResponse::ok` if loading succeeded, otherwise the reason it failed
   */
  SF2::IO::LoadResponse load();

  /// @returns the embedded name in the file
  std::string embeddedName() const;

  /// @returns the embedded author name in the file
  std::string embeddedAuthor() const;

  /// @returns any embedded comment in the file
  std::string embeddedComment() const;

  /// @returns any embedded copyright notice in the file
  std::string embeddedCopyright() const;

  /// @returns the number of presets found in the file
  size_t size() const noexcept;

  /**
   Obtain an `SF2PresetInfo` for the preset at the given index, in bank/program order. The index is checked: Swift
   does no bounds checking on a C++ subscript, and this used to read past the end for a bad index or before `load`.

   @param index the preset to reference
   @returns SF2PresetInfo for the indicated preset, or no value if `index` is not less than `size()`
   */
  std::optional<SF2PresetInfo> operator[](size_t index) const;

private:
  std::unique_ptr<SF2::IO::File> impl_;
  std::string path_;
};
