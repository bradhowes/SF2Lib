// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <vector>

#include "SF2Lib/Entity/Bag.hpp"
#include "SF2Lib/Entity/Generator/Generator.hpp"
#include "SF2Lib/Entity/Instrument.hpp"
#include "SF2Lib/Entity/Modulator/Modulator.hpp"
#include "SF2Lib/Entity/Preset.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Entity/Version.hpp"

#include "SF2Lib/IO/ChunkItems.hpp"
#include "SF2Lib/Render/SampleSourceCollection.hpp"

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

  /**
   Constructor. Processes the SF2 file contents and builds up various collections based on what it finds.

   @param path the file to open and load
   */
  File(const char* path);

  /**
   Constructor. Processes the SF2 file contents and builds up various collections based on what it finds.

   @param path the file to open and load
   */
  File(std::string path);

  /**
   Custom destructor. Closes file that was opened in constructor.
   */
  ~File() noexcept;

  enum class LoadResponse {
    ok,
    notFound,
    invalidFormat
  };

  /**
   Load the file given in the constructor. Note that most of the File API is valid only if that load was successful
   and returned `LoadResponse::ok`.

   @returns status of the load
   */
  LoadResponse load() noexcept;

  /// @returns true if the file has been loaded successfully.
  bool loaded() const noexcept { return fd_ != -1; }

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

  /// @returns reference to collection of SampleSource entities.
  const Render::SampleSourceCollection& sampleSourceCollection() const noexcept {
    return sampleSourceCollection_;
  }

  /// @returns reference to collection of preset indices that order the Preset entities by bank and program.
  const std::vector<size_t>& presetIndicesOrderedByBankProgram() const noexcept {
    return presetIndicesOrderedByBankProgram_;
  }

  void patchReleaseTimes(float maxDuration) noexcept;

  void dumpThreaded() const noexcept;

  void dump() const noexcept;

private:

  std::string path_;
  int fd_{-1};
  off_t size_{0};
  off_t sampleDataBegin_{0};
  off_t sampleDataEnd_{0};
  Entity::Version soundFontVersion_{};
  Entity::Version fileVersion_{};

  std::string soundEngine_{};
  std::string embeddedName_{};
  std::string embeddedCreationDate_{};
  std::string embeddedAuthor_{};
  std::string embeddedProduct_{};
  std::string embeddedCopyright_{};
  std::string embeddedComment_{};
  std::string embeddedTools_{};

  ChunkItems<Entity::Preset> presets_{};
  ChunkItems<Entity::Bag> presetZones_{};
  ChunkItems<Entity::Generator::Generator> presetZoneGenerators_{};
  ChunkItems<Entity::Modulator::Modulator> presetZoneModulators_{};
  ChunkItems<Entity::Instrument> instruments_{};
  ChunkItems<Entity::Bag> instrumentZones_{};
  ChunkItems<Entity::Generator::Generator> instrumentZoneGenerators_{};
  ChunkItems<Entity::Modulator::Modulator> instrumentZoneModulators_{};
  ChunkItems<Entity::SampleHeader> sampleHeaders_{};
  Render::SampleSourceCollection sampleSourceCollection_{sampleHeaders_};

  std::vector<size_t> presetIndicesOrderedByBankProgram_{};
};

} // end namespace SF2::IO
