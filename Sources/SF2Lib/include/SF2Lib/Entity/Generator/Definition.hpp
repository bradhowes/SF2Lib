// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <string>

#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/Entity/Generator/Amount.hpp"
#include "SF2Lib/Entity/Generator/Index.hpp"

namespace SF2::Entity::Generator {

/**
 Meta data for SF2 generators. These are attributes associated with a generator but that are not found in an SF2 file.
 Rather these are attributes called out in the SF2 specification or to make the rendering implementation easier to
 understand.
 */
class Definition {
public:

  /// Range for generator values. Default is no range checking.
  struct ValueRange {

    /// @returns true if the range is valid
    bool isValid() const noexcept { return min < max; }

    /**
     Clamp the given value to be within the defined range. If range is not valid, no clamping will take place.

     @param value the value to clamp
     @returns clamped value if range is valid, or original value.
     */
    template <typename T> T clamp(T value) const noexcept {
      return isValid() ? std::min<T>(std::max<T>(value, min), max) : value;
    }

    int min{};
    int max{};
  };

  static constexpr size_t NumDefs = static_cast<size_t>(Index::numValues);

  /// The kind of value held by the generator
  enum struct ValueKind {

    // These have isUnsignedValue() == true
    unsignedShort = 1,
    offset,
    coarseOffset,

    // These have isUnsignedValue() == false
    signedShort,
    signedCents,
    signedCentsBel,
    unsignedPercent,
    signedPercent,
    signedFrequencyCents,
    signedTimeCents,
    signedSemitones,

    // Two 8-int bytes
    range
  };

  /**
   Obtain the Definition entry for a given Index value

   @param index value to lookup
   @returns Definition entry
   */
  static const Definition& definition(Index index) { return definitions_.at(static_cast<size_t>(index)); }

  /// @returns name of the definition
  const std::string& name() const noexcept { return name_; }

  /// @returns value type of the generator
  ValueKind valueKind() const noexcept { return valueKind_; }

  /// @returns true if the generator can be used in a preset zone
  bool isAvailableInPreset() const noexcept { return availableInPreset_; }

  /**
   Obtain the NRPN multiplier for a generator index. Per SF 2.01 spec:

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
  uint8_t nrpnMultiplier() const noexcept { return nrpnMultiplier_; }

  /// @returns true if the generator amount value is unsigned or signed
  bool isUnsignedValue() const noexcept { return valueKind_ < ValueKind::signedShort; }

  /**
   Obtain the value from a generator Amount instance. Properly handles unsigned integer values.

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
      case ValueKind::signedCents: return valueOf(amount) / 1200.0f;

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

  void dump(const Amount& amount) const noexcept;

private:
  static std::array<Definition, NumDefs> const definitions_;

  Definition(const char* name, ValueKind valueKind, ValueRange minMax, bool availableInPreset,
             uint8_t nrpnMultiplier) noexcept :
  name_{name}, valueKind_{valueKind}, valueRange_{minMax}, availableInPreset_{availableInPreset},
  nrpnMultiplier_{nrpnMultiplier} {}

  std::string name_;
  ValueKind valueKind_;
  ValueRange valueRange_;
  bool availableInPreset_;
  uint8_t nrpnMultiplier_;
};

} // end namespace SF2::Entity::Generator
