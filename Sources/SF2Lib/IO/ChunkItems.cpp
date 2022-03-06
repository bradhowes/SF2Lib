// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>
#include <unistd.h>

#include "SF2Lib/IO/ChunkItems.hpp"

using namespace SF2::IO;

void
ChunkItemsSupport::beginDump(size_t size)
{
  std::cout << " count: " << size << std::endl;
}

