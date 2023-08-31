// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Entity/Entity.hpp"
#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"

/**
 Classes involved in describing an SF2 generator that provides or "generates" a value that is used to render audio.
 */
namespace SF2::Entity::Generator {

/**
 Memory layout of a 'pgen'/'igen' entry. The size of this is defined to be 4. Each instance represents a generator
 configuration.
 */
class Generator : public Entity {
public:
  static constexpr size_t entity_size = 4;

  /**
   Constructor from file.

   @param pos location in file to read
   */
  explicit Generator(IO::Pos& pos) noexcept;

  /// @returns index of the generator as an enumerated type
  Index index() const noexcept { return index_.index(); }

  /// @returns value configured for the generator
  Amount amount() const noexcept { return amount_; }

  /// @returns meta-data for the generator
  const Definition& definition() const noexcept;

  /// @returns the name of the generator
  const std::string& name() const noexcept;

  /// @returns the configured value of a generator
  int value() const noexcept { return definition().valueOf(amount_); }

  std::ostream& dump(const std::string& indent, size_t index) const noexcept;

private:
  RawIndex index_;
  Amount amount_;
};

} // end namespace SF2::Entity::Generator
