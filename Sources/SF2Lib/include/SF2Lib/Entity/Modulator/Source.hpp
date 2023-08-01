// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <cstdlib>
#include <iostream>
#include <string>

namespace SF2::Entity::Modulator {

/**
 The source of an SF2 modulator. There are two types:

 - general controller
 - MIDI continuous controller (CC)

 The type is defined by the CC flag (bit 7). The general type points to various common MIDI values as a source of
 modulation, while the CC type allows for a broader collection of controllers.
 */
class Source {
public:

  /// Valid sources for a general controller
  enum struct GeneralIndex : uint16_t {
    none = 0,
    noteOnVelocity = 2,
    noteOnKey = 3,
    keyPressure = 10,
    channelPressure = 13,
    pitchWheel = 14,
    pitchWheelSensitivity = 16,
  };

  /// Transformations applied to values that come from a source
  enum struct ContinuityType : uint16_t {
    linear = 0,
    concave,
    convex,
    switched
  };

  enum struct ControllerRange: uint16_t {
    _128 = 128,
    _8192 = 8192
  };

  /// Continuous Controller (CC) designation
  struct CC {
    explicit CC(uint16_t v) : value{v} {}
    uint16_t value;
  };

  /// The bit that flags a CC index
  inline static constexpr uint16_t ccBit = (1 << 7);
  /// Bit mask for the index
  inline static constexpr uint16_t indexMask = ccBit - 1;
  /// The bit that flags the direction of the controller mapping
  inline static constexpr uint16_t directionBit = (1 << 8);
  /// The bit that flags the polarity of the controller mapping
  inline static constexpr uint16_t polarityBit = (1 << 9);

  /// Default constructor that maps to an inactive source (one that always returns 0.0)
  Source() noexcept : bits_{0} {}

  /**
   Generate a Source based on a MIDI general controller.

   @param index the controller to use
   */
  explicit Source(GeneralIndex index) noexcept : bits_{static_cast<uint16_t>(uint16_t(index) & indexMask)} {}

  /**
   Generate a Source based on a MIDI continuous controller (CC)
   */
  explicit Source(CC cc) noexcept : bits_{static_cast<uint16_t>((cc.value & indexMask) | ccBit)} {}

  /// Generate new Source that flows in the increasing direction
  Source positive() const noexcept { return Source(bits_ & ~directionBit); }
  /// Generate new Source that flows in the decreasing direction
  Source negative() const noexcept { return Source(bits_ |  directionBit); }
  /// Generate new Source that is unipolar [0 - 1]
  Source unipolar() const noexcept { return Source(bits_ & ~polarityBit); }
  /// Generate new Source that is bipolar [-1 - +1]
  Source bipolar()  const noexcept { return Source(bits_ |  polarityBit); }
  /// Generate new Source that is linear
  Source linear() noexcept { return continuity(ContinuityType::linear); }
  /// Generate new Source that is concave
  Source concave() noexcept { return continuity(ContinuityType::concave); }
  /// Generate new Source that is convex
  Source convex() noexcept { return continuity(ContinuityType::convex); }
  /// Generate new Source that is gated (either 0/-1 or 1)
  Source switched() noexcept { return continuity(ContinuityType::switched); }

  /// @returns true if the source is valid
  bool isValid() const noexcept {
    if (rawType() > static_cast<uint16_t>(ContinuityType::switched)) {
      return false;
    }
    auto idx = rawIndex();
    if (isContinuousController()) {
      return !(idx == 0 || idx == 6 || (idx >=32 && idx <= 63) || idx == 98 || idx == 101 ||
               (idx >= 120 && idx <= 127));
    } else {
      return idx == 0 || idx == 2 || idx == 3 || idx == 10 || idx == 13 || idx == 14 || idx == 16 || idx == 127;
    }
  }

  /// @returns true if the source is a continuous controller (CC)
  bool isContinuousController() const noexcept { return (bits_ & ccBit) ? true : false; }
  /// @returns true if the source is a general controller
  bool isGeneralController() const noexcept { return !isContinuousController(); }
  /// @returns true if the source acts in a unipolar manner
  bool isUnipolar() const noexcept { return polarity() == 0; }
  /// @returns true if the source acts in a bipolar manner
  bool isBipolar() const noexcept { return !isUnipolar(); }
  /// @returns true if the source values go from small to large as the controller goes from min to max
  bool isPositive() const noexcept { return direction() == 0; }
  /// @returns true if the source values go from large to small as the controller goes from min to max
  bool isNegative() const noexcept { return !isPositive(); }

  /// @returns the index of the general controller
  GeneralIndex generalIndex() const noexcept {
    assert(isValid() && isGeneralController());
    return GeneralIndex(rawIndex());
  }

  /// @returns largest value the controller will return.
  ControllerRange controllerRange() const noexcept {
    if (!isContinuousController() && generalIndex() == GeneralIndex::pitchWheel) return ControllerRange::_8192;
    return ControllerRange::_128;
  }
  
  /// @returns the index of the continuous controller
  int ccIndex() const noexcept {
    assert(isValid() && isContinuousController());
    return rawIndex();
  }

  /// @returns the continuity type for the controller values
  ContinuityType type() const noexcept {
    assert(isValid());
    return ContinuityType(rawType());
  }
  
  /// @returns the name of the continuity type
  std::string continuityTypeName() const noexcept { return isValid() ? std::string(typeNames[rawType()]) : "N/A"; }
  /// @returns a description of the Source
  std::string description() const noexcept;
  
  bool operator ==(const Source& rhs) const noexcept { return bits_ == rhs.bits_; }
  bool operator !=(const Source& rhs) const noexcept { return bits_ != rhs.bits_; }

  friend std::ostream& operator<<(std::ostream& os, const Source& mod) noexcept;

private:
  explicit Source(uint16_t bits) : bits_{bits} {}

  Source continuity(ContinuityType continuity) const noexcept {
    return Source(static_cast<uint16_t>((bits_ & 0x3FF) | (uint16_t(continuity) << 10)));
  }

  static constexpr char const* typeNames[] = { "linear", "concave", "convex", "switched" };

  uint16_t rawIndex() const noexcept { return bits_ & indexMask; }
  uint16_t rawType() const noexcept { return bits_ >> 10; }
  uint16_t polarity() const noexcept { return bits_ & polarityBit; }
  uint16_t direction() const noexcept { return bits_ & directionBit; }

  uint16_t bits_;
};

} // end namespace SF2::Entity::Modulator
