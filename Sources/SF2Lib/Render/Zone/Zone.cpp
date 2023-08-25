// Copyright © 2022 Brad Howes. All rights reserved.

#include <limits>

#include "SF2Lib/Render/Zone/Zone.hpp"

using namespace SF2::Render::Zone;

MIDIRange const Zone::all = MIDIRange(0, 255);

Zone::Zone(GeneratorCollection&& gens, ModulatorCollection&& mods, Entity::Generator::Index terminal) :
generators_{std::move(gens)},
modulators_{std::move(mods)},
keyRange_{GetKeyRange(generators_)},
velocityRange_{GetVelocityRange(generators_)},
isGlobal_{IsGlobal(generators_, terminal, modulators_)}
{
  if (generators_.empty() && modulators_.empty()) throw std::runtime_error("empty zone created");
}

bool
Zone::IsGlobal(const GeneratorCollection& gens, Entity::Generator::Index expected,
               const ModulatorCollection& mods) noexcept
{
  assert(!gens.empty() || !mods.empty());
  return (gens.empty() && !mods.empty()) || (!gens.empty() && gens.back().get().index() != expected);
}

uint16_t
Zone::resourceLink() const
{
  if (isGlobal_)
    throw std::runtime_error("global zones do not have a linked resource");
  const Entity::Generator::Generator& generator{generators_.back().get()};
  assert(generator.index() == Entity::Generator::Index::instrument ||
         generator.index() == Entity::Generator::Index::sampleID);
  return generator.amount().unsignedAmount();
}

MIDIRange
Zone::GetKeyRange(const GeneratorCollection& generators) noexcept
{
  if (generators.size() > 0 && generators[0].get().index() == Entity::Generator::Index::keyRange) {
    return MIDIRange(generators[0].get().amount());
  }
  return all;
}

MIDIRange
Zone::GetVelocityRange(const GeneratorCollection& generators) noexcept
{
  int index = -1;
  if (generators.size() > 1 && generators[0].get().index() == Entity::Generator::Index::keyRange &&
      generators[1].get().index() == Entity::Generator::Index::velocityRange) {
    index = 1;
  }
  else if (generators.size() > 0 && generators[0].get().index() == Entity::Generator::Index::velocityRange) {
    index = 0;
  }
  return index == -1 ? all : MIDIRange(generators[size_t(index)].get().amount());
}
