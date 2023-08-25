// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Entity/Bag.hpp"
#include "SF2Lib/Render/SampleSourceCollection.hpp"
#include "SF2Lib/Render/Zone/Zone.hpp"

namespace SF2::Render::Zone {

/**
 A specialization of a Zone for an Instrument. Non-global instrument zones must have a sample source which provides the
 raw samples used for rendering.
 */
class Instrument : public Zone {
public:

  /**
   Construct new instrument zone from entity in file.

   @param gens the vector of generators that define the zone
   @param mods the vector of modulators that define the zone
   @param sampleSources the samples for all of the instruments in the SF2 file
   */
  Instrument(GeneratorCollection&& gens, ModulatorCollection&& mods,
             const SampleSourceCollection& sampleSources) noexcept;

  /// @returns the sample buffer registered to this zone. Throws exception if zone is global
  const Render::Voice::Sample::NormalizedSampleSource& sampleSource() const;

  /**
   Apply the instrument zone to the given voice state. Sets the nominal value of the generators in the zone.

   @param state the voice state to update
   */
  void apply(Voice::State::State& state) const noexcept;

private:
  const Render::Voice::Sample::NormalizedSampleSource* sampleSource_;
};

} // namespace SF2::Render
