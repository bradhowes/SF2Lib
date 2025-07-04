// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <concepts>

#include "SF2Lib/Render/Zone/Collection.hpp"

namespace SF2::IO { class File; }
namespace SF2::Render {

template <typename T>
concept ZoneDerivedType = std::derived_from<T, SF2::Render::Zone::Zone>;

/**
 Base class for entities that contain a collection of zones (there are two: Render::Preset and Render::Instrument).
 Contains common properties and methods shared between these two classes.

 - `T` is an SF2::Zone class (PresetZone or InstrumentZone) to hold in the collection
 - `E` is the SF2::Entity class that defines the zone configuration in the SF2 file.

 Must be derived from.
 */
template <ZoneDerivedType T, EntityDerivedType E>
class WithCollectionBase
{
public:
  using ZoneType = T;
  using EntityType = E;
  using CollectionType = Zone::Collection<ZoneType>;

  /// @returns true if the instrument has a global zone
  bool hasGlobalZone() const noexcept { return zones_.hasGlobal(); }

  /// @returns the collection's global zone if there is one
  const ZoneType* globalZone() const noexcept { return zones_.global(); }

  /// @returns the collection of zones associated with the child class
  const CollectionType& zones() const noexcept { return zones_; }

  /// @returns the preset/instrument's entity from the SF2 file
  const EntityType& configuration() const noexcept { return configuration_; }

protected:
  WithCollectionBase(size_t zoneCount, const EntityType& configuration) noexcept :
  zones_{zoneCount}, configuration_{configuration} {}

  CollectionType zones_;

private:
  const EntityType& configuration_;
};

} // namespace SF2::Render
