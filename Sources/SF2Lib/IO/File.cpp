// Copyright © 2022 Brad Howes. All rights reserved.

#include <fstream>
#include <iostream>
#include <map>
#include <memory>

#include "SF2Lib/Entity/Instrument.hpp"
#include "SF2Lib/Entity/Preset.hpp"
#include "SF2Lib/IO/ChunkList.hpp"
#include "SF2Lib/IO/File.hpp"

using namespace SF2::IO;

File::File(std::string path) :
path_{path},
fd_{-1}
{
}

File::File(const char* path) : File::File(std::string(path)) {}

File::~File() noexcept
{
  if (fd_ >= 0) ::close(fd_);
}


struct Closer
{
  explicit Closer(int fd) : fd_{fd} {}

  ~Closer() { if (is_valid()) ::close(fd_); }

  int operator *() const { return fd_; }

  bool is_valid() const { return fd_ != -1; }

  int release() noexcept {
    int tmp = -1;
    std::swap(tmp, fd_);
    return tmp;
  }

private:
  int fd_{-1};
};


File::LoadResponse
File::load() noexcept
{
  if (fd_ != -1) return LoadResponse::ok;

  // FIXME: this will not work one iOS devices I do not think
  // Strip off the 'file://' bit if present.
  auto pos = path_.find("file://");
  auto c_path = path_.c_str() + (pos == std::string::npos ? 0 : 7);

  std::clog << "trying to open: " << c_path << '\n';
  auto fd = Closer(::open(c_path, O_RDONLY));
  if (!fd.is_valid()) {
    std::clog << "failed to open - " << strerror(errno) << '\n';
    return LoadResponse::notFound;
  }

  off_t fileSize = ::lseek(*fd, 0, SEEK_END);
  if (fileSize < 16) return LoadResponse::invalidFormat;

  size_ = fileSize;
  sampleDataBegin_ = 0;
  sampleDataEnd_ = 0;
  rawSamples_.clear();

  try {
    auto riff = Pos(*fd, 0, size_).makeChunkList();
    if (riff.tag() != Tags::riff || riff.kind() != Tags::sfbk) throw File::LoadResponse::invalidFormat;
    auto p0 = riff.begin();
    while (p0 < riff.end()) {
      auto chunkList = p0.makeChunkList();
      if (chunkList.tag() != Tags::list) throw File::LoadResponse::invalidFormat;
      if (chunkList.kind() != Tags::info &&
          chunkList.kind() != Tags::sdta &&
          chunkList.kind() != Tags::pdta) throw File::LoadResponse::invalidFormat;
      auto p1 = chunkList.begin();
      p0 = chunkList.advance();
      while (p1 < chunkList.end()) {
        auto chunk = p1.makeChunk();
        p1 = chunk.advance();
        switch (chunk.tag().toTags()) {
          case Tags::ifil: soundFontVersion_.load(chunk.begin()); break;
          case Tags::isng: soundEngine_ = chunk.extract(); break;
          case Tags::iver: fileVersion_.load(chunk.begin()); break;
          case Tags::inam: embeddedName_ = chunk.extract(); break;
          case Tags::icrd: embeddedCreationDate_ = chunk.extract(); break;
          case Tags::ieng: embeddedAuthor_ = chunk.extract(); break;
          case Tags::iprd: embeddedProduct_ = chunk.extract(); break;
          case Tags::icop: embeddedCopyright_ = chunk.extract(); break;
          case Tags::icmt: embeddedComment_ = chunk.extract(); break;
          case Tags::istf: embeddedTools_ = chunk.extract(); break;
          case Tags::phdr: presets_.load(chunk); break;
          case Tags::pbag: presetZones_.load(chunk); break;
          case Tags::pgen: presetZoneGenerators_.load(chunk); break;
          case Tags::pmod: presetZoneModulators_.load(chunk); break;
          case Tags::inst: instruments_.load(chunk); break;
          case Tags::ibag: instrumentZones_.load(chunk); break;
          case Tags::igen: instrumentZoneGenerators_.load(chunk); break;
          case Tags::imod: instrumentZoneModulators_.load(chunk); break;
          case Tags::shdr: sampleHeaders_.load(chunk); break;
          case Tags::smpl: chunk.extractSamples(rawSamples_); break;
          default:
            break;
        }
      }
    }
  } catch (File::LoadResponse) {
    return LoadResponse::invalidFormat;
  }

  // Create a indirection index that provides the presets ordered by bank/program ordering.
  presetIndicesOrderedByBankProgram_.resize(presets_.size());
  std::iota(presetIndicesOrderedByBankProgram_.begin(), presetIndicesOrderedByBankProgram_.end(), 0);
  std::sort(presetIndicesOrderedByBankProgram_.begin(), presetIndicesOrderedByBankProgram_.end(),
            [&](size_t aIndex, size_t bIndex) {
    return presets_[aIndex] < presets_[bIndex];
  });

  // Build the collection of normalized samples.
  sampleSourceCollection_.build(rawSamples_.data());

  fd_ = fd.release();
  return LoadResponse::ok;
}

void
File::dump() const noexcept {
  std::cout << "|-ifil"; soundFontVersion_.dump("|-ifil");
  std::cout << "|-iver"; fileVersion_.dump("|-iver");

  std::cout << "|-phdr"; presets_.dump("|-phdr: ");
  std::cout << "|-pbag"; presetZones_.dump("|-pbag: ");
  std::cout << "|-pgen"; presetZoneGenerators_.dump("|-pgen: ");
  std::cout << "|-pmod"; presetZoneModulators_.dump("|-pmod: ");
  std::cout << "|-inst"; instruments_.dump("|-inst: ");
  std::cout << "|-ibag"; instrumentZones_.dump("|-ibag: ");
  std::cout << "|-igen"; instrumentZoneGenerators_.dump("|-igen: ");
  std::cout << "|-imod"; instrumentZoneModulators_.dump("|-imod: ");
  std::cout << "|-shdr"; sampleHeaders_.dump("|-shdr: ");
}

void
File::dumpThreaded() const noexcept {
  std::map<int, int> instrumentLines;
  int lineCounter = 1;
  for (size_t phdrIndex = 0; phdrIndex < presets_.size(); ++phdrIndex) {
    const auto& preset{presets_[phdrIndex]};

    // Dump preset header
    preset.dump("phdr", phdrIndex); ++lineCounter;
    for (size_t pbagIndex = 0; pbagIndex < preset.zoneCount(); ++pbagIndex) {

      // Dump preset zone. If the zone's generator set is empty or does not end with a link to an instrument, it
      // is global.
      const auto& pbag{presetZones_[pbagIndex + preset.firstZoneIndex()]};
      if (pbag.generatorCount() == 0 ||
          presetZoneGenerators_[pbag.firstGeneratorIndex() + pbag.generatorCount() - 1].index() !=
          Entity::Generator::Index::instrument) {
        pbag.dump(" PBAG", pbagIndex + preset.firstZoneIndex()); ++lineCounter;
      }
      else {
        pbag.dump(" pbag", pbagIndex + preset.firstZoneIndex()); ++lineCounter;
      }

      // Dump the modulators for the zone. Per spec, this should be empty
      for (size_t pmodIndex = 0; pmodIndex < pbag.modulatorCount(); ++pmodIndex) {
        const auto& pmod{presetZoneModulators_[pmodIndex + pbag.firstModulatorIndex()]};
        pmod.dump("  pmod", pmodIndex + pbag.firstModulatorIndex()); ++lineCounter;
      }

      // Dump the generators for the zone.
      for (size_t pgenIndex = 0; pgenIndex < pbag.generatorCount(); ++pgenIndex) {
        const auto& pgen{presetZoneGenerators_[pgenIndex + pbag.firstGeneratorIndex()]};
        pgen.dump("  pgen", pgenIndex + pbag.firstGeneratorIndex()); ++lineCounter;

        // If the (last) generator is for an instrument, dump out the instrument.
        if (pgen.index() == Entity::Generator::Index::instrument) {
          auto instrumentIndex = pgen.amount().unsignedAmount();
          const auto& inst{instruments_[instrumentIndex]};
          inst.dump("   inst", instrumentIndex); ++lineCounter;

          // See if we have already dumped out the contents of the instrument's zones
          auto found = instrumentLines.find(instrumentIndex);
          if (found != instrumentLines.end()) {
            std::cout << "   inst *** see line " << found->second << std::endl; ++lineCounter;
            continue;
          }

          instrumentLines.insert(std::pair(instrumentIndex, lineCounter - 1));
          for (size_t ibagIndex = 0; ibagIndex < inst.zoneCount(); ++ibagIndex) {

            // Dump instrument zone. If the zone's generator set is empty or does not end with a link to a
            // sample header, it is global.
            const auto& ibag{instrumentZones_[ibagIndex + inst.firstZoneIndex()]};
            if (ibag.generatorCount() == 0 ||
                instrumentZoneGenerators_[ibag.firstGeneratorIndex() + ibag.generatorCount() - 1].index() !=
                Entity::Generator::Index::sampleID) {
              ibag.dump("    IBAG", ibagIndex + inst.firstZoneIndex()); ++lineCounter;
            }
            else {
              ibag.dump("    ibag", ibagIndex + inst.firstZoneIndex()); ++lineCounter;
            }

            // Dump the modulator definitions for the zone
            for (size_t imodIndex = 0; imodIndex < ibag.modulatorCount(); ++imodIndex) {
              const auto& imod{instrumentZoneModulators_[imodIndex + ibag.firstModulatorIndex()]};
              imod.dump("     imod", imodIndex + ibag.firstModulatorIndex()); ++lineCounter;
            }

            // Dump the generators for the zone
            for (size_t igenIndex = 0; igenIndex < ibag.generatorCount(); ++igenIndex) {
              const auto& igen{instrumentZoneGenerators_[igenIndex + ibag.firstGeneratorIndex()]};
              igen.dump("     igen", igenIndex + ibag.firstGeneratorIndex()); ++lineCounter;

              // If the (last) generator is for a sample, dump the sample header.
              if (igen.index() == Entity::Generator::Index::sampleID) {
                auto sampleIndex = igen.amount().unsignedAmount();
                const auto& shdr{sampleHeaders_[sampleIndex]};
                shdr.dump("      shdr", sampleIndex); ++lineCounter;
              }
            }
          }
        }
      }
    }
  }
}
