// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <functional>
#include <vector>

#include "SF2Lib/Entity/Bag.hpp"
#include "SF2Lib/Entity/Generator/Generator.hpp"
#include "SF2Lib/Entity/Modulator/Modulator.hpp"
#include "SF2Lib/IO/ChunkItems.hpp"
#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Zone/Zone.hpp"

namespace SF2::Render::Zone {

/**
 Templated collection of zones, made up of either Preset zones or Instrument zones. A non-global zone defines a range
 of MIDI keys and/or velocities over which it operates. The first zone can be a `global` zone. The global zone defines
 the configuration settings that apply to all other zones. The collection can be filtered by MIDI key and velocity to
 obtain the zones that are to be used for rendering audio samples.
 */
template <typename T>
class Collection
{
public:
  using GeneratorCollection = typename T::GeneratorCollection;
  using ModulatorCollection = typename T::ModulatorCollection;
  using Matches = typename std::vector<std::reference_wrapper<T const>>;

  /**
   Construct a new collection that expects to hold the given number of elements.

   @param zoneCount the number of zones that the collection will hold
   */
  explicit Collection(size_t zoneCount) noexcept : zones_{} { zones_.reserve(zoneCount); }

  /// @returns number of zones in the collection (including the optional global one)
  size_t size() const noexcept { return zones_.size(); }

  /**
   Locate the zone(s) that match the given key/velocity pair.

   @param key the MIDI key to filter on
   @param velocity the MIDI velocity to filter on
   @returns a vector references to matching zones
   */
  Matches filter(int key, int velocity) const noexcept
  {
    Matches matches;
    auto pos = zones_.cbegin();
    if (hasGlobal()) ++pos;
    std::copy_if(pos, zones_.cend(), std::back_inserter(matches),
                 [key, velocity](const Zone& zone) { return zone.appliesTo(key, velocity); });
    return matches;
  }

  /// @returns true if first zone in collection is a global zone
  bool hasGlobal() const noexcept { return !zones_.empty() && zones_.front().isGlobal(); }

  /// @returns pointer to global zone or nullptr if there is not one
  const T* global() const noexcept { return hasGlobal() ? &zones_.front() : nullptr; }

  /**
   Add a zone with the given args. Note that empty zones (no generators and no modulators) are dropped, as are any
   global zones that are not the first zone.

   @param notGlobalIfPresent generator index that if present at end of gen collection means the zone is not global. For
   a PresetZone, this is an Instrument. For an InstrumentZone, it is a SampleSource.
   @param gens collection of generators that defines the zone
   @param mods collection of modulators that defines the zone
   @param values additional arguments for the Zone construction
   */
  template<class... Args>
  void add(Entity::Generator::Index notGlobalIfPresent, GeneratorCollection&& gens, ModulatorCollection&& mods,
           const Args&... values) noexcept {

    // Per spec, disregard zones that have no gens AND mods
    if (gens.empty() && mods.empty()) return;

    // Per spec, only one global zone allowed and it must be the first one.
    if (Zone::IsGlobal(gens, notGlobalIfPresent, mods) && !zones_.empty()) return;

    zones_.emplace_back(std::forward<decltype(gens)>(gens), std::forward<decltype(mods)>(mods), values...);
  }

private:
  std::vector<T> zones_;
};

} // namespace SF2::Render
