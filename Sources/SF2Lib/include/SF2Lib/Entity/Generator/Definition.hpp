// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <string>

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Entity/Generator/Amount.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"

namespace SF2::Entity::Generator {

/**
 Meta data for SF2 generators.

 These are the attributes associated with a generator but that are not found in an SF2 file. Rather they are those
 spelled out in the SoundFont spec or to make the rendering implementation easier to understand.

 Each entry has the following attributes

 - name -- the name of the generator (based off its Generator::Index enum value)
 - valueKind -- describes the underlying value held by the generator when it comes from the SF2 file
 - isAvailableInPreset -- `true` if the value can be provided in a preset; `false` if only from an instrument
 - nrpnMultiplier -- the scaling factor to apply to an MIDI NRPN value that is mapped to the generator

 */
class Definition {
public:

  /// Range for generator values. Default is no range checking.
  struct ValueRange {

    constexpr ValueRange(int _min, int _max) : min{_min}, max{_max} {}

    /**
     Clamp the given value to be within the defined range.

     @param value the value to clamp
     @returns clamped value
     */
    template <typename T> T clamp(T value) const noexcept { return std::clamp<T>(value, min, max); }

    const int min;
    const int max;
  };

  /// Number of definitions. This is the same as the number of generators defined in the SF2 spec.
  static constexpr size_t NumDefs = static_cast<size_t>(Index::numValues);

  /// The kind of value held by the generator
  enum struct ValueKind {

    // These have isUnsignedValue() == true
    unsignedShort = 1,
    offset,
    coarseOffset,
    unsignedPercent,

    // These have isUnsignedValue() == false
    signedShort,
    signedCents,
    signedCentsBel,
    signedPercent,
    signedFrequencyCents,
    signedTimeCents,
    signedSemitones,

    // Two 8-int bytes
    range,

    // Unused value
    UNUSED
  };

  /// Scaling factor for NRPN values that affect a generator. This is for MIDI 1.0 messages where the range of an
  /// NRPN controller is -/+ 8192 (14 bits). See below for the `nrpnMultiplier` method.
  enum struct NRPNMultiplier {
    x1 = 1,
    x2 = 2,
    x4 = 4
  };

  /**
   Obtain the Definition entry for a given Index value

   @param index value to lookup
   @returns Definition entry
   */
  static const Definition& definition(Index index) { return definitions_[index]; }

  /// @returns name of the definition
  const std::string& name() const noexcept { return name_; }

  /// @returns value type of the generator
  ValueKind valueKind() const noexcept { return valueKind_; }

  /// @returns true if the generator can be used in a preset zone
  bool isAvailableInPreset() const noexcept { return availableInPreset_; }

  /**
   Obtain the NRPN multiplier for a generator index. Per SF 2.01 spec section 9.6.3:

   Data Entry value spans the “useful” range as outlined in section 8.1.3, and in the same
   perceptually-additive-real-world units. In the case where the meaningful range consists of more than 8192
   perceptually-additive-real-world units, the range of the NRPN control of that parameter is decreased by a factor of
   two until the adjusted range consists of 8192 or less of the perceptually-additive-real-world units. In the case
   where the meaningful range consists of less than 8192 perceptually- additive-real-world units, the range of the
   NRPN control of that parameter is left unchanged, and the synthesizer may or may not permit the control to exceed
   that range.

   In other words, we have 14 bits to indicate a signed NRPN value, which means +/- 8192. Some generators cover larger
   ranges, so for those, we will reduce resolution by multiplying the NPRN value with a multiplier large enough to
   cover the generator range (1, 2 or 4).

   @returns multiplier for NRPN values.
  */
  int nrpnMultiplier() const noexcept { return static_cast<int>(nrpnMultiplier_); }

  /// @returns true if the generator amount value is unsigned or signed
  bool isUnsignedValue() const noexcept { return valueKind_ < ValueKind::signedShort; }

  /**
   Obtain the value from a generator Amount instance.

   @param amount the container holding the value to extract
   @returns extracted value
   */
  int valueOf(const Amount& amount) const noexcept {
    return isUnsignedValue() ? amount.unsignedAmount() : amount.signedAmount();
  }

  /**
   Obtain the value from a generator Amount instance (from an SF2 file) after converting it to its natural or desired
   form.

   @param amount the container holding the value to extract
   @returns the converted value
   */
  Float convertedValueOf(const Amount& amount) const noexcept {
    switch (valueKind_) {
      case ValueKind::coarseOffset: return valueOf(amount) * 32768;
      case ValueKind::signedCents: return Float(valueOf(amount) / 1200.0f);

      case ValueKind::signedCentsBel:
      case ValueKind::unsignedPercent:
      case ValueKind::signedPercent: return valueOf(amount) / 10.0f;

      case ValueKind::signedFrequencyCents: return Float(DSP::centsToFrequency(valueOf(amount)));
      case ValueKind::signedTimeCents: return DSP::centsToSeconds(valueOf(amount));

      default: return valueOf(amount);
    }
  }

  /**
   Clamp a given value to the defined range for the generator.

   @param value the value to clamp
   @returns clamped value
   */
  template <typename T> T clamp(T value) const noexcept { return valueRange_.clamp(value); }

  std::ostream& dump(const Amount& amount) const noexcept;

private:
  static GeneratorValueArray<Definition> const definitions_;

  Definition(const char* name, ValueKind valueKind, ValueRange minMax, bool availableInPreset,
             NRPNMultiplier nrpnMultiplier) noexcept :
  name_{name}, valueKind_{valueKind}, valueRange_{minMax}, availableInPreset_{availableInPreset},
  nrpnMultiplier_{nrpnMultiplier} {}

  std::string name_;
  ValueKind valueKind_;
  ValueRange valueRange_;
  bool availableInPreset_;
  NRPNMultiplier nrpnMultiplier_;
};

} // end namespace SF2::Entity::Generator
