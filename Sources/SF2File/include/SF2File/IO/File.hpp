// Copyright © 2022, 2025, 2026 Brad Howes. All rights reserved.

#pragma once

#include <vector>

#include "SF2File/Entity/Bag.hpp"
#include "SF2File/Entity/Generator/Generator.hpp"
#include "SF2File/Entity/Instrument.hpp"
#include "SF2File/Entity/Modulator/Modulator.hpp"
#include "SF2File/Entity/Preset.hpp"
#include "SF2File/Entity/SampleHeader.hpp"
#include "SF2File/Entity/Version.hpp"

#include "SF2File/IO/ChunkItems.hpp"
#include "SF2File/IO/SampleSourceCollection.hpp"
#include "SF2File/IO/UniqueFd.hpp"

/**
 Collection of classes and types involved in parsing an SF2 file or data stream.
 */
namespace SF2::IO {

/**
 Represents an SF2 file. The constructor will process the entire file to validate its integrity and record the
 locations of the nine entities that define an SF2 file. It also extracts certain meta data items from various chunks
 such as the embedded name, author, and copyright statement.
 */
class File {
public:
  File() = default;

  /**
   Constructor.

   NOTE: legacy API that only saves the path. Requires call to ``load()`` to do anything meaningful.

   @param path the file to open and load
   */
  File(const char* path);

  /**
   Constructor.

   NOTE: legacy API that only saves the path. Requires call to ``load()`` to do anything meaningful.

   @param path the file to open and load
   */
  File(std::string path);

  File(const File&) = delete;

  File(File&& rhs) noexcept = default;

  /// Closes the file if it was loaded successfully.
  ~File() = default;

  enum class LoadResponse: int {
    ok = 0,
    notFound = 1,
    invalidFormat = 2,
    none = -1
  };

  /**
   Load the file given in the constructor. Note that most of the File API is valid only if `load` was successful
   and returned `LoadResponse::ok`.

   @returns status of the load
   */
  LoadResponse load() noexcept;

  /**
   Load the file by the given file descriptor. Note that most of the File API is valid only if `load` was successful
   and returned `LoadResponse::ok`.

   The descriptor is duplicated: the caller keeps ownership of `fd` and may close it as soon as this returns. The
   duplicate stays open for as long as this instance exists, since samples are read from it lazily.

   @param fd the file descriptor of the file to read from
   @returns status of the load
   */
  LoadResponse load(int fd) noexcept;

  /// @returns true if the file has been loaded successfully.
  bool loaded() const noexcept { return loaded_; }

  /// @returns the embedded name in the file
  const std::string& embeddedName() const noexcept { return embeddedName_; }

  /// @returns the embedded author name in the file
  const std::string& embeddedAuthor() const noexcept { return embeddedAuthor_; }

  /// @returns any embedded comment in the file
  const std::string& embeddedComment() const noexcept { return embeddedComment_; }

  /// @returns any embedded copyright notice in the file
  const std::string& embeddedCopyright() const noexcept { return embeddedCopyright_; }

  /// @returns reference to preset definitions found in the file
  const ChunkItems<Entity::Preset>& presets() const noexcept { return presets_; };

  /// @returns reference to preset zone definitions
  const ChunkItems<Entity::Bag>& presetZones() const noexcept { return presetZones_; };

  /// @returns reference to preset zone generator definitions
  const ChunkItems<Entity::Generator::Generator>& presetZoneGenerators() const noexcept {
    return presetZoneGenerators_;
  };

  /// @returns reference to preset zone modulator definitions
  const ChunkItems<Entity::Modulator::Modulator>& presetZoneModulators() const noexcept {
    return presetZoneModulators_;
  };

  /// @returns reference to instrument definitions found in the file
  const ChunkItems<Entity::Instrument>& instruments() const noexcept { return instruments_; };

  /// @returns reference to instrument zone definitions
  const ChunkItems<Entity::Bag>& instrumentZones() const noexcept { return instrumentZones_; };

  /// @returns reference to instrument zone generator definitions
  const ChunkItems<Entity::Generator::Generator>& instrumentZoneGenerators() const noexcept {
    return instrumentZoneGenerators_;
  };

  /// @returns reference to instrument zone modulator definitions
  const ChunkItems<Entity::Modulator::Modulator>& instrumentZoneModulators() const noexcept {
    return instrumentZoneModulators_;
  };

  /// @returns reference to samples definitions
  const ChunkItems<Entity::SampleHeader>& sampleHeaders() const noexcept { return sampleHeaders_; };

  /// @returns reference to collection of preset indices that order the Preset entities by bank and program.
  const std::vector<size_t>& presetIndicesOrderedByBankProgram() const noexcept {
    return presetIndicesOrderedByBankProgram_;
  }

  Pos sampleDataBegin() const noexcept { return sampleDataBegin_; }

  void patchReleaseTimes(float maxDuration) noexcept;

  void dumpThreaded() const noexcept;

  void dump() const;

private:
  /**
   Check the cross-references between the loaded entity lists.

   @throws LoadResponse::invalidFormat if any index is out of range
   */
  void validate() const;

  /**
   Load the file using the given descriptor. On success the descriptor is kept open until this instance is destroyed;
   on failure it is closed.

   @param fd the descriptor to read from
   @returns status of the load
   */
  LoadResponse load(UniqueFd&& fd) noexcept;

  std::string path_;
  UniqueFd fd_{};
  bool loaded_{false};
  off_t size_{0};
  Pos sampleDataBegin_{-1, 0, 0};

  Entity::Version soundFontVersion_{};

  std::string soundEngine_{};
  std::string embeddedName_{};
  std::string embeddedCreationDate_{};
  std::string embeddedAuthor_{};
  std::string embeddedProduct_{};
  std::string embeddedCopyright_{};
  std::string embeddedComment_{};

  ChunkItems<Entity::Preset> presets_{};
  ChunkItems<Entity::Bag> presetZones_{};
  ChunkItems<Entity::Generator::Generator> presetZoneGenerators_{};
  ChunkItems<Entity::Modulator::Modulator> presetZoneModulators_{};
  ChunkItems<Entity::Instrument> instruments_{};
  ChunkItems<Entity::Bag> instrumentZones_{};
  ChunkItems<Entity::Generator::Generator> instrumentZoneGenerators_{};
  ChunkItems<Entity::Modulator::Modulator> instrumentZoneModulators_{};
  ChunkItems<Entity::SampleHeader> sampleHeaders_{};

  std::vector<size_t> presetIndicesOrderedByBankProgram_{};

  os_log_t log_{Log::create("File")};
};

} // end namespace SF2::IO
