// Copyright © 2022 Brad Howes. All rights reserved.

#include <string>

#include "SF2File/Entity/Preset.hpp"

#include "SF2File/IO/ChunkList.hpp"
#include "SF2File/IO/File.hpp"
#include "SF2File/IO/Parser.hpp"

using namespace SF2::IO;

Parser::Info
Parser::parse(const char* path)
{
  int fd = ::open(path, O_RDONLY);
  if (fd == -1) throw File::LoadResponse::notFound;

  Parser::Info info;
  off_t fileSize = ::lseek(fd, 0, SEEK_END);

  auto riff = Pos(fd, 0, fileSize).makeChunkList();
  auto p0 = riff.begin();
  while (p0 < riff.end()) {
    auto chunkList = p0.makeChunkList();
    auto p1 = chunkList.begin();
    p0 = chunkList.advance();
    while (p1 < chunkList.end()) {
      auto chunk = p1.makeChunk();
      p1 = chunk.advance();
      switch (chunk.tag().toTags()) {

        case Tags::inam:
          info.embeddedName = chunk.extract();
          break;

        case Tags::icop:
          info.embeddedCopyright = chunk.extract();
          break;

        case Tags::ieng:
          info.embeddedAuthor = chunk.extract();
          break;

        case Tags::icmt:
          info.embeddedComment = chunk.extract();
          break;

        case Tags::phdr:
        {
          auto presets = ChunkItems<Entity::Preset>();
          presets.load(chunk);
          info.presets.reserve(presets.size());
          for (auto const& sfp : presets) {
            info.presets.emplace_back(sfp.name(), sfp.bank(), sfp.program());
          }
        }
          break;

        default:
          break;
      }
    }
  }

  if (info.presets.empty()) throw File::LoadResponse::invalidFormat;
  return info;
}
