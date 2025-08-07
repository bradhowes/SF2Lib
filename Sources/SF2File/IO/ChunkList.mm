// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>
#include <unistd.h>
#include <vector>

#include "SF2File/IO/ChunkList.hpp"
#include "SF2File/IO/File.hpp"

using namespace SF2::IO;

ChunkList::ChunkList(Tag tag, uint32_t size, Tag kind, Pos pos) :
Chunk(tag, size, pos), kind_{kind}
{
  auto available = pos.available();
  if (size > available) throw File::LoadResponse::invalidFormat;
}
