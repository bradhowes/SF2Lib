// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>
#include <string>

#include "SF2File/Entity/Bag.hpp"
#include "SF2File/IO/Pos.hpp"

using namespace SF2::Entity;

Bag::Bag(IO::Pos& pos)
{
  // Read only the 4-byte file record: the counts that follow it are not in the file.
  pos = pos.readInto(*this, entity_size);
}

void
Bag::dump(const std::string& indent, size_t index) const
{
  std::cout << indent << '[' << index << "] genIndex: " << firstGeneratorIndex() << " count: " << generatorCount()
  << " modIndex: " << firstModulatorIndex() << " count: " << modulatorCount() << std::endl;
}
