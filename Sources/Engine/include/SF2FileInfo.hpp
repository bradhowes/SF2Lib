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
  /**
   Construct new instance with the contents from the given file.

   @param path the location of the file to load
   */
  SF2FileInfo(std::string path);

  /**
   Attempt to load the file pointed to in the constructor.

   @returns `true` if loading succeeded, `false` otherwise
   */
  bool load();

  /// @returns the embedded name in the file
  std::string embeddedName() const noexcept SWIFT_RETURNS_INDEPENDENT_VALUE;

  /// @returns the embedded author name in the file
  std::string embeddedAuthor() const noexcept SWIFT_RETURNS_INDEPENDENT_VALUE;

  /// @returns any embedded comment in the file
  std::string embeddedComment() const noexcept SWIFT_RETURNS_INDEPENDENT_VALUE;

  /// @returns any embedded copyright notice in the file
  std::string embeddedCopyright() const noexcept SWIFT_RETURNS_INDEPENDENT_VALUE;

  /// @returns the number of presets found in the file
  size_t size() const noexcept;

  /**
   Obtain an `SF2PresetInfo` for the preset at the given index.

   @param index the preset to reference. Must be between 0 and size() - 1.
   @returns SF2PresetInfo for the indicated preset
   */
  SF2PresetInfo operator[](size_t index) const noexcept SWIFT_RETURNS_INDEPENDENT_VALUE;

private:
  std::unique_ptr<SF2::IO::File> impl_;
  std::string path_;
} SWIFT_SELF_CONTAINED;
