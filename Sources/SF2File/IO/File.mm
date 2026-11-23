// Copyright © 2022 Brad Howes. All rights reserved.

#include <fstream>
#include <iostream>
#include <map>
#include <memory>
#include <numeric>
#include <type_traits>

#include "DSPHeaders/Accelerated.hpp"

#include "SF2File/Entity/Instrument.hpp"
#include "SF2File/Entity/Preset.hpp"
#include "SF2File/IO/ChunkList.hpp"
#include "SF2File/IO/File.hpp"

using namespace SF2::IO;

File::File(std::string path) noexcept : path_{path} {}

File::File(const char* path) noexcept : File::File(std::string(path)) {}

File::LoadResponse
File::load() noexcept
{
  static const std::string prefix = "file://";

  std::cout << "loading: " << path_ << std::endl;

  // NOTE: not sure about this being the best approach when on iOS. Probably better to use Foundation FileManager to
  // open the file and hopefully obtain a low-level file descriptor that we can then use to process the contents.
  auto offset = path_.find(prefix) == std::string::npos ? 0 : prefix.size();
  auto c_path = path_.c_str() + offset;

  if (loaded_) return LoadResponse::ok;
  auto fd = UniqueFd::openForReading(c_path);
  if (!fd.isValid()) return LoadResponse::notFound;

  return load(std::move(fd));
}

File::LoadResponse
File::load(int fd) noexcept
{
  if (loaded_) return LoadResponse::ok;

  // Work with our own descriptor so that the caller can close theirs (e.g. when an NSFileHandle goes away) without
  // breaking the lazy sample loading done later by `Preset::loadSamples`.
  return load(UniqueFd::duplicate(fd));
}

namespace {
[[noreturn]] void reject() { throw File::LoadResponse::invalidFormat; }

/**
 Validate the zone indices of a PHDR/INST collection and its PBAG/IBAG collection. Each owner's zones are the bags in
 [firstZoneIndex, next owner's firstZoneIndex), and each bag's generators and modulators run up to the next bag's
 indices, so the indices must not decrease and the terminal records must not point past the end of the next list.
 */
template <typename Owners>
void validateZones(const Owners& owners, const ChunkItems<SF2::Entity::Bag>& bags, size_t generatorCount, size_t modulatorCount) {
  for (size_t index = 0; index < owners.size(); ++index) {
    if (owners[index + 1].firstZoneIndex() < owners[index].firstZoneIndex()) reject();
  }
  if (owners[owners.size()].firstZoneIndex() > bags.size()) reject();

  for (size_t index = 0; index < bags.size(); ++index) {
    if (bags[index + 1].firstGeneratorIndex() < bags[index].firstGeneratorIndex()) reject();
    if (bags[index + 1].firstModulatorIndex() < bags[index].firstModulatorIndex()) reject();
  }
  if (bags[bags.size()].firstGeneratorIndex() > generatorCount) reject();
  if (bags[bags.size()].firstModulatorIndex() > modulatorCount) reject();
}

} // namespace


File::LoadResponse
File::load(UniqueFd&& owned) noexcept
{
  if (loaded_) return LoadResponse::ok;
  if (!owned.isValid()) return LoadResponse::invalidFormat;

  auto fd = owned.get();
  off_t fileSize = ::lseek(fd, 0, SEEK_END);
  if (fileSize < 16) return LoadResponse::invalidFormat;

  size_ = fileSize;
  auto hasIFIL = false;

  try {
    auto riff = Pos(fd, 0, size_).makeChunkList();
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
          case Tags::ifil:
            if (chunk.size() != 4) throw File::LoadResponse::invalidFormat;
            soundFontVersion_.load(chunk.begin());
            hasIFIL = true;
            break;
          case Tags::isng: soundEngine_ = chunk.extract(); break;
          case Tags::inam: embeddedName_ = chunk.extract(); break;
          case Tags::icrd: embeddedCreationDate_ = chunk.extract(); break;
          case Tags::ieng: embeddedAuthor_ = chunk.extract(); break;
          case Tags::iprd: embeddedProduct_ = chunk.extract(); break;
          case Tags::icop: embeddedCopyright_ = chunk.extract(); break;
          case Tags::icmt: embeddedComment_ = chunk.extract(); break;
          case Tags::phdr: presets_.load(chunk); break;
          case Tags::pbag: presetZones_.load(chunk); break;
          case Tags::pgen: presetZoneGenerators_.load(chunk); break;
          case Tags::pmod: presetZoneModulators_.load(chunk); break;
          case Tags::inst: instruments_.load(chunk); break;
          case Tags::ibag: instrumentZones_.load(chunk); break;
          case Tags::igen: instrumentZoneGenerators_.load(chunk); break;
          case Tags::imod: instrumentZoneModulators_.load(chunk); break;
          case Tags::shdr: sampleHeaders_.load(chunk); break;
          case Tags::smpl:
            // Limit reads to the `smpl` chunk so that sample headers cannot reach into `pdta` (or past the file end).
            sampleDataBegin_ = chunk.begin().limit(off_t(chunk.size()));
            break;
          default:
            break;
        }
      }
    }
    if (!hasIFIL) reject();
    validate();
  } catch (File::LoadResponse) {
    sampleDataBegin_ = Pos(-1, 0, 0);
    return LoadResponse::invalidFormat;
  } catch (const std::exception&) {
    // For instance, std::bad_alloc from a chunk that claims to hold more entities than we can allocate.
    sampleDataBegin_ = Pos(-1, 0, 0);
    return LoadResponse::invalidFormat;
  }

  // Keep the descriptor open for as long as this instance exists: `sampleDataBegin_` (and therefore
  // `Preset::loadSamples`) reads from it.
  fd_ = std::move(owned);

  // Create an indirection index that provides the presets ordered by bank/program ordering.
  presetIndicesOrderedByBankProgram_.resize(presets_.size());
  std::iota(presetIndicesOrderedByBankProgram_.begin(), presetIndicesOrderedByBankProgram_.end(), 0);
  std::stable_sort(presetIndicesOrderedByBankProgram_.begin(), presetIndicesOrderedByBankProgram_.end(),
                   [&](size_t aIndex, size_t bIndex) {
    return presets_[aIndex] < presets_[bIndex];
  });

  loaded_ = true;
  return LoadResponse::ok;
}

void
File::validate() const
{
  using Entity::Generator::Index;

  // SF2.01 7.2, 7.6, 7.10: there must be at least one preset, and the PHDR, PBAG, INST, IBAG and SHDR lists must each
  // end with a terminal record. The generator and modulator lists may be empty as long as no bag refers to them.
  if (presets_.empty() || !presetZones_.hasTerminal() || !instruments_.hasTerminal() ||
      !instrumentZones_.hasTerminal() || !sampleHeaders_.hasTerminal()) reject();

  validateZones(presets_, presetZones_, presetZoneGenerators_.size(), presetZoneModulators_.size());
  validateZones(instruments_, instrumentZones_, instrumentZoneGenerators_.size(), instrumentZoneModulators_.size());

  // SF2.01 7.5: an instrument generator whose value is not a valid instrument index means the file should be rejected.
  for (const auto& generator : presetZoneGenerators_) {
    if (generator.index() == Index::instrument && generator.amount().unsignedAmount() >= instruments_.size()) reject();
  }

  // SF2.01 7.9: likewise for sampleID generators and sample headers. The referenced sample must also lie within the
  // `smpl` chunk, since its samples are read from there.
  auto sampleCount = size_t(sampleDataBegin_.available()) / sizeof(int16_t);
  for (const auto& generator : instrumentZoneGenerators_) {
    if (generator.index() != Index::sampleID) continue;
    auto sampleIndex = generator.amount().unsignedAmount();
    if (sampleIndex >= sampleHeaders_.size()) reject();
    const auto& header = sampleHeaders_[sampleIndex];
    // SF2.01 5.4, 5.5, 7.10: ROM samples refer to sample memory we do not have. The spec asks for such zones to be
    // silent; with no ROM support at all we reject the file instead. Only headers that an instrument uses are checked.
    if (header.isROM()) reject();
    if (header.startIndex() > header.endIndex() || header.endIndex() > sampleCount) reject();
  }
}

void
File::dump() const noexcept {
  std::cout << "|-ifil"; soundFontVersion_.dump("|-ifil");
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
