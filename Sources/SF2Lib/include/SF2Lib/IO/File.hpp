// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <fstream>
#include <map>
#include <memory>
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
  File(const char* path) : path_{path}, fd_{-1}
  {
    fd_ = ::open(path, O_RDONLY);
    if (fd_ == -1) throw std::runtime_error("file not found");
    if (load() != LoadResponse::ok) throw Format::error;
  }

  /**
   Custom destructor. Closes file that was opened in constructor.
   */
  ~File() noexcept
  {
    if (fd_ >= 0) ::close(fd_);
  }

  File(const File&) = delete;
  File(File&&) = delete;
  File& operator =(const File&) = delete;
  File& operator =(File&&) = delete;

  enum class LoadResponse {
    ok,
    notFound,
    invalidFormat
  };

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

  const Render::SampleSourceCollection& sampleSourceCollection() const noexcept {
    return sampleSourceCollection_;
  }

  void patchReleaseTimes(float maxDuration) noexcept;
  
  void dumpThreaded() const noexcept;

  void dump() const noexcept;

private:

  LoadResponse load();

  std::string path_;
  int fd_;
  off_t size_;
  off_t sampleDataBegin_;
  off_t sampleDataEnd_;
  Entity::Version soundFontVersion_;
  Entity::Version fileVersion_;

  std::string soundEngine_;
  std::string rom_;
  std::string embeddedName_;
  std::string embeddedCreationDate_;
  std::string embeddedAuthor_;
  std::string embeddedProduct_;
  std::string embeddedCopyright_;
  std::string embeddedComment_;
  std::string embeddedTools_;

  ChunkItems<Entity::Preset> presets_;
  ChunkItems<Entity::Bag> presetZones_;
  ChunkItems<Entity::Generator::Generator> presetZoneGenerators_;
  ChunkItems<Entity::Modulator::Modulator> presetZoneModulators_;
  ChunkItems<Entity::Instrument> instruments_;
  ChunkItems<Entity::Bag> instrumentZones_;
  ChunkItems<Entity::Generator::Generator> instrumentZoneGenerators_;
  ChunkItems<Entity::Modulator::Modulator> instrumentZoneModulators_;
  ChunkItems<Entity::SampleHeader> sampleHeaders_;

  Render::SampleSourceCollection sampleSourceCollection_;
  std::vector<int16_t> rawSamples_;
};

} // end namespace SF2::IO
