// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <functional>
#include <vector>
#include <utility>

#include "SF2Lib/Entity/Bag.hpp"
#include "SF2Lib/Entity/Generator/Generator.hpp"
#include "SF2Lib/Entity/Modulator/Modulator.hpp"
#include "SF2Lib/IO/ChunkItems.hpp"
#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Range.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render::Zone {

using MIDIRange = Range<int>;

/**
 A zone represents a collection of generator and modulator settings that apply to a range of MIDI key and velocity
 values. There are two types: instrument zones and preset zones. Generator settings for the former specify actual values
 to use, while those in preset zones define adjustments to values set by the instrument.

 Must be derived from, but it defines no virtual functions.
 */
class Zone
{
public:
  using GeneratorCollection = IO::ChunkItems<Entity::Generator::Generator>::ItemRefCollection;
  using ModulatorCollection = IO::ChunkItems<Entity::Modulator::Modulator>::ItemRefCollection;

  /// A range that always returns true for any MIDI value.
  static MIDIRange const all;

  /**
   Determine if the generator collection and modulator collection combo refers to a global zone. This is the
   case iff the generator collection is empty and the modulator collection is not, or the generator collection does
   not end with a generator of an expected type. Note that in particular if *both* collections are empty, it is *not* a
   global zone here (it should be filtered out elsewhere)

   @param gens collection of generator for the zone
   @param expected the index type of a generator that signals the zone is NOT global
   @param mods collection of modulators for the zone
   */
  static bool IsGlobal(const GeneratorCollection& gens, Entity::Generator::Index expected,
                       const ModulatorCollection& mods) noexcept;

  /// @returns range of MID key values that this Zone handles
  const MIDIRange& keyRange() const noexcept { return keyRange_; }

  /// @returns range of MIDI velocity values that this Zone handles
  const MIDIRange& velocityRange() const noexcept { return velocityRange_; }

  /// @returns collection of generators defined for this zone
  const GeneratorCollection& generators() const noexcept { return generators_; }

  /// @returns collection of modulators defined for this zone
  const ModulatorCollection& modulators() const noexcept { return modulators_; }

  /// @returns true if this is a global zone
  bool isGlobal() const noexcept { return isGlobal_; }

  /**
   Determines if this zone applies to a given MIDI key/velocity pair. NOTE: this should not be called for a global
   zone, though technically doing so is OK since both key/velocity ranges will be set to `all` by default.

   @param key MIDI key value
   @param velocity MIDI velocity value
   @returns true if so
   */
  bool appliesTo(int key, int velocity) const noexcept {
    return keyRange_.contains(key) && velocityRange_.contains(velocity);
  }

protected:

  /**
   Constructor.

   @param gens collection of generator for the zone
   @param mods collection of modulators for the zone
   @param terminal the index type of a generator that signals the zone is NOT global
   */
  Zone(GeneratorCollection&& gens, ModulatorCollection&& mods, Entity::Generator::Index terminal);

  /**
   Obtain the link to the resource used by this zone. For an instrument zone, this points to the sample buffer to
   use to render sounds. For a preset zone, this points to an instrument. It is undefined to call on a global zone.

   @returns index of the resource that this zone uses
   */
  uint16_t resourceLink() const;

private:

  /**
   Obtain a key range from a generator collection. Per spec, if it exists it must be the first generator.

   @param generators collection of generators for the zone
   @returns key range if found or `all` if not
   */
  static MIDIRange GetKeyRange(const GeneratorCollection& generators) noexcept;

  /**
   Obtain a velocity range from a generator collection. Per spec, if it exists it must be the first OR second
   generator, and it can only be the second if the first is a key range generator.

   @param generators collection of generators for the zone
   @returns velocity range if found or `all` if not
   */
  static MIDIRange GetVelocityRange(const GeneratorCollection& generators) noexcept;

  GeneratorCollection generators_;
  ModulatorCollection modulators_;
  MIDIRange keyRange_;
  MIDIRange velocityRange_;
  bool isGlobal_;
};

} // namespace SF2::Render
