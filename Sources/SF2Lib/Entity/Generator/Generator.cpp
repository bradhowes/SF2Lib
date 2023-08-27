// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Entity/Generator/Amount.hpp"
#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Entity/Generator/Generator.hpp"
#include "SF2Lib/IO/Pos.hpp"

using namespace SF2::Entity::Generator;

Generator::Generator(IO::Pos& pos) noexcept
{
  pos = pos.readInto(*this);
}

struct Dumper {
  const Definition& genDef_;
  const Amount& amount_;

  explicit Dumper(const Definition& genDef, const Amount& amount) noexcept : genDef_{genDef}, amount_{amount} {}

  friend std::ostream& operator <<(std::ostream& os, const Dumper& dumper) noexcept
  {
    dumper.genDef_.dump(dumper.amount_);
    return os;
  }
};

const Definition&
Generator::definition() const noexcept
{
  return Definition::definition(index_.index());
}

const std::string&
Generator::name() const noexcept
{
  return definition().name();
}

std::ostream&
Generator::dump(const std::string& indent, size_t index) const noexcept
{
  return std::cout << indent << '[' << index << "] " << name() << ' ' << Dumper(definition(), amount_) << std::endl;
}
