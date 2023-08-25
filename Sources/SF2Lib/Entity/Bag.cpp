// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>
#include <string>

#include "SF2Lib/Entity/Bag.hpp"
#include "SF2Lib/IO/Pos.hpp"

using namespace SF2::Entity;

Bag::Bag(IO::Pos& pos) noexcept
{
  assert(sizeof(*this) == 4);
  pos = pos.readInto(*this);
}

size_t
Bag::generatorCount() const noexcept
{
  int value = (this + 1)->firstGeneratorIndex() - firstGeneratorIndex();
  assert(value >= 0);
  return static_cast<size_t>(value);
}

size_t
Bag::modulatorCount() const noexcept
{
  int value = (this + 1)->firstModulatorIndex() - firstModulatorIndex();
  assert(value >= 0);
  return static_cast<size_t>(value);
}

void
Bag::dump(const std::string& indent, size_t index) const noexcept
{
  std::cout << indent << '[' << index << "] genIndex: " << firstGeneratorIndex() << " count: " << generatorCount()
  << " modIndex: " << firstModulatorIndex() << " count: " << modulatorCount() << std::endl;
}
