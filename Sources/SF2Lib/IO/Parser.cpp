// Copyright © 2022 Brad Howes. All rights reserved.

#include <string>

#include "SF2Lib/Entity/Preset.hpp"

#include "SF2Lib/IO/ChunkList.hpp"
#include "SF2Lib/IO/Format.hpp"
#include "SF2Lib/IO/Parser.hpp"

using namespace SF2::IO;

Parser::Info
Parser::parse(const char* path)
{
  int fd = ::open(path, O_RDONLY);
  if (fd == -1) throw Format::error;

  Parser::Info info;
  off_t fileSize = ::lseek(fd, 0, SEEK_END);

  auto riff = Pos(fd, 0, fileSize).makeChunkList();
  if (riff.tag() != Tags::riff) throw Format::error;
  if (riff.kind() != Tags::sfbk) throw Format::error;

  auto p0 = riff.begin();
  while (p0 < riff.end()) {
    auto chunkList = p0.makeChunkList();
    auto p1 = chunkList.begin();
    p0 = chunkList.advance();
    while (p1 < chunkList.end()) {
      auto chunk = p1.makeChunk();
      p1 = chunk.advance();
      auto p2 = p1;
      switch (Tags(chunk.tag().rawValue())) {
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
          p2 = chunk.begin();
          while (p2 < chunk.end()) {
            Entity::Preset sfp(p2);
            info.presets.emplace_back(sfp.name(), sfp.bank(), sfp.program());
          }
          info.presets.pop_back();
          break;

        default:
          break;
      }
    }
  }

  if (info.presets.empty()) throw Format::error;
  return info;
}
