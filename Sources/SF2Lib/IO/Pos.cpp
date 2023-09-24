// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/IO/ChunkList.hpp"
#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/IO/Pos.hpp"

using namespace SF2::IO;

Pos::SeekProcType Pos::SeekProc = &::lseek;
Pos::ReadProcType Pos::ReadProc = &::read;

Pos::Pos(int fd, off_t pos, off_t end) noexcept :
fd_{fd},
pos_{pos},
end_{end}
{
  ;
}

Pos
Pos::readInto(void* buffer, size_t count) const
{
  if (Pos::seek(fd_, off_t(pos_), SEEK_SET) != off_t(pos_)) throw File::LoadResponse::invalidFormat;
  off_t result = Pos::read(fd_, buffer, count);
  if (result != long(count)) throw File::LoadResponse::invalidFormat;
  return advance(result);
}

Pos
Pos::advance(off_t offset) const noexcept
{
  return Pos(fd_, std::min(pos_ + offset, end_), end_);
}

Chunk
Pos::makeChunk() const
{
  uint32_t buffer[2];
  if (Pos::seek(fd_, off_t(pos_), SEEK_SET) != off_t(pos_)) throw File::LoadResponse::invalidFormat;
  if (Pos::read(fd_, buffer, sizeof(buffer)) != sizeof(buffer)) throw File::LoadResponse::invalidFormat;
  return Chunk(Tag(buffer[0]), buffer[1], advance(sizeof(buffer)));
}

ChunkList
Pos::makeChunkList() const
{
  uint32_t buffer[3];
  if (Pos::seek(fd_, off_t(pos_), SEEK_SET) != off_t(pos_)) throw File::LoadResponse::invalidFormat;
  if (Pos::read(fd_, buffer, sizeof(buffer)) != sizeof(buffer)) throw File::LoadResponse::invalidFormat;
  return ChunkList(Tag(buffer[0]), buffer[1] - 4, Tag(buffer[2]), advance(sizeof(buffer)));
}
