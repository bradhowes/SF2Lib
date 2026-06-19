// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2File/IO/Pos.hpp"
#include "SF2File/Entity/Generator/Definition.hpp"
#include "SF2File/Entity/Generator/Index.hpp"

/**
 Classes involved in describing an SF2 generator that provides or "generates" a value that is used to control some aspect of
 the audio rendering process.
 */
namespace SF2::Entity::Generator {

/**
 Memory layout of a 'pgen'/'igen' entry. The size of this is defined to be 4. Each instance represents a generator
 configuration.
 */
class Generator {
public:
  static inline const size_t entity_size = 4;

  /**
   Construct from file.

   @param pos location in file to read. Note the given value is updated to point to the the location after the read.
   */
  explicit Generator(IO::Pos& pos) noexcept;

  /// @returns index of the generator as an enumerated type
  inline Index index() const noexcept { return index_.index(); }

  /// @returns value configured for the generator
  inline Amount amount() const noexcept { return amount_; }

  /// @returns meta-data for the generator
  const Definition& definition() const noexcept;

  /// @returns the name of the generator
  const std::string& name() const noexcept;

  /// @returns the configured value of a generator
  inline int value() const noexcept { return definition().valueOf(amount_); }

  std::ostream& dump(const std::string& indent, size_t index) const noexcept;

private:
  RawIndex index_;
  Amount amount_;
};

} // end namespace SF2::Entity::Generator
