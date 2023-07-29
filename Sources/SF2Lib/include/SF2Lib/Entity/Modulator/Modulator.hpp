// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <string>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/IO/Pos.hpp"
#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Entity/Modulator/Source.hpp"
#include "SF2Lib/Entity/Modulator/Transform.hpp"

/**
 Classes involved in describing an SF2 modulator. A modulator uses a value from a source to modulate a specific
 generator's value.
 */
namespace SF2::Entity::Modulator {

/**
 Memory layout of a 'pmod'/'imod' entry. The size of this is defined to be 10.

 Defines a mapping of a modulator to a generator so that a modulator can affect the value given by a generator. Per the
 spec a modulator can have two sources. If the first one is 'none', then the modulator will always return 0.0. The
 second one is optional -- if it exists then it will scale the result of the previous source value. Otherwise, it just
 acts as if the source returned 1.0.

 Per the spec, modulators are unique if they do not share the same sfModSrcOper, sfModDestOper, sfModAmtSrcOper values.
 If there are duplicates, the second occurrence wins.
 */
class Modulator {
public:
  static constexpr size_t size = 10;

  inline static constexpr uint16_t modulatorDestinationBit = 1 << 15;

  /**
   Default modulators that are predefined for every instrument. These get copied over to each voice's State before the
   preset/instrument configurations are applied.
   */
  static const std::array<Modulator, size> defaults;

  /**
   Construct instance from contents of SF2 file.

   @param pos location to read from
   */
  explicit Modulator(IO::Pos& pos) noexcept {
    assert(sizeof(*this) == size);
    pos = pos.readInto(*this);
  }

  /**
   Construct instance from values. Used to define default mods and support unit tests.

   @param modSrcOper the source of the modulation
   @param dest the Generator that is being modulated
   @param amount the amount of modulation to apply
   @param modAmtSrcOper the source of the modulation of the amount value
   @param transform the transformation to apply to modulated values.
   */
  Modulator(Source modSrcOper, Generator::Index dest, int16_t amount, Source modAmtSrcOper,
            Transformer transform) noexcept :
  sfModSrcOper{modSrcOper}, sfModDestOper{static_cast<uint16_t>(dest)}, modAmount{amount},
  sfModAmtSrcOper{modAmtSrcOper}, sfModTransOper{transform} {}

  /**
   Construct instance from values. Used to support unit tests.
   */
  Modulator(Source modSrcOper, int link, int16_t amount, Source modAmtSrcOper,
            Transformer transform) noexcept :
  sfModSrcOper{modSrcOper}, sfModDestOper{static_cast<uint16_t>(link | modulatorDestinationBit)}, modAmount{amount},
  sfModAmtSrcOper{modAmtSrcOper}, sfModTransOper{transform} {}

  /// @returns the source of data for the modulator
  const Source& source() const noexcept { return sfModSrcOper; }

  /// @returns true if this modulator is the source of a value for another modulator
  bool hasModulatorDestination() const noexcept { return (sfModDestOper & modulatorDestinationBit) != 0; }

  /// @returns true if this modulator directly affects a generator value
  bool hasGeneratorDestination() const noexcept { return !hasModulatorDestination(); }

  /// @returns the destination (generator) for the modulator
  Generator::Index generatorDestination() const noexcept {
    assert(hasGeneratorDestination() && sfModDestOper < size_t(Generator::Index::numValues));
    return Generator::Index(sfModDestOper);
  }

  /// @returns the index of the destination modulator. This is the index in the pmod/imod bag.
  size_t linkDestination() const noexcept {
    assert(hasModulatorDestination());
    return size_t(sfModDestOper ^ modulatorDestinationBit);
  }

  /// @returns the maximum deviation that a modulator can apply to a generator
  int16_t amount() const noexcept { return modAmount; }

  /// @returns the second source of data for the modulator
  const Source& amountSource() const noexcept { return sfModAmtSrcOper; }

  /// @returns the transform to apply to values created by the modulator
  const Transformer& transformer() const noexcept { return sfModTransOper; }

  /// @returns textual description of the modulator
  std::string description() const noexcept;

  /**
   Compare two instances for equality.

   @param rhs the modulator to compare with
   @returns true if this modulator is equivalent to `rhs`
   */
  bool operator ==(const Modulator& rhs) const noexcept {
    return (sfModSrcOper == rhs.sfModSrcOper && sfModDestOper == rhs.sfModDestOper &&
            sfModAmtSrcOper == rhs.sfModAmtSrcOper);
  }

  /**
   Compare two instances for inequality.

   @param rhs the modulator to compare with
   @return true if this modulator is not equivalent to `rhs`
   */
  bool operator !=(const Modulator& rhs) const noexcept {  return !operator==(rhs); }

  void dump(const std::string& indent, size_t index) const noexcept;

private:
  Source sfModSrcOper;
  uint16_t sfModDestOper;
  int16_t modAmount;
  Source sfModAmtSrcOper;
  Transformer sfModTransOper;
};

} // end namespace SF2::Entity::Modulator
