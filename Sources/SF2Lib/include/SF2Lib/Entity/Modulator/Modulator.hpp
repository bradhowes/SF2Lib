// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <string>

#include "SF2Lib/Entity/Entity.hpp"
#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Entity/Modulator/Source.hpp"
#include "SF2Lib/Entity/Modulator/Transformer.hpp"

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
 If there are duplicates, the second occurrence wins. This is also how modulators can override those that were defined
 either by default or in an instrument or preset zone.
 */
class Modulator : public Entity {
public:
  inline static constexpr size_t size = 10;

  /// Number of default modulators
  inline static constexpr size_t DefaultsSize = 10;

  /**
   Default modulators that are predefined for every instrument. These get copied over to each voice's State before the
   preset/instrument configurations are applied.
   */
  static const std::array<Modulator, DefaultsSize> defaults;

  /**
   Construct instance from contents of SF2 file.

   @param pos location to read from
   */
  explicit Modulator(IO::Pos& pos) noexcept;

  /**
   Construct instance from values. Used to define default mods and support unit tests.

   @param modSrcOper the source of the modulation
   @param dest the Generator that is being modulated
   @param amount the amount of modulation to apply
   @param modAmtSrcOper the source of the modulation of the amount value
   @param transform the transformation to apply to modulated values.
   */
  Modulator(Source modSrcOper, Generator::Index dest, int16_t amount, Source modAmtSrcOper = Source(),
            Transformer transform = Transformer()) noexcept;

  /// @returns the source of data for the modulator
  const Source& source() const noexcept { return sfModSrcOper; }

  /// @returns the destination (generator) for the modulator
  Generator::Index generatorDestination() const noexcept {
    return Generator::Index(sfModDestOper);
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
   Compare two instances for equality. Per the SF2 spec, the `modAmount` and `sfModTransOper` are not involved in this.

   @param rhs the modulator to compare with
   @returns true if this modulator is equivalent to `rhs`
   */
  bool operator ==(const Modulator& rhs) const noexcept {
    return (sfModSrcOper == rhs.sfModSrcOper &&
            sfModDestOper == rhs.sfModDestOper &&
            sfModAmtSrcOper == rhs.sfModAmtSrcOper);
  }

  /**
   Compare two instances for inequality.

   @param rhs the modulator to compare with
   @return true if this modulator is not equivalent to `rhs`
   */
  bool operator !=(const Modulator& rhs) const noexcept { return !operator==(rhs); }

  void dump(const std::string& indent, size_t index) const noexcept;

private:
  Source sfModSrcOper;
  uint16_t sfModDestOper;
  int16_t modAmount;
  Source sfModAmtSrcOper;
  Transformer sfModTransOper;
};

} // end namespace SF2::Entity::Modulator
