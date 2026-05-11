// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2File/Entity/SampleHeader.hpp"
#include "SF2File/IO/ChunkItems.hpp"
#include "SF2Lib/Render/Zone/Zone.hpp"
#include "SF2Lib/Render/Zone/NormalizedSamples.hpp"

namespace SF2::Render::Zone {

/**
 A specialization of a Zone for an Instrument. Non-global instrument zones must have a sample header that defines where the
 raw samples are in the SF2 file. When a preset is loaded, the instrument will acquire a `NormalizedSampleSource` entry that
 holds the actual samples to use for rendering.
 */
class Instrument : public Zone {
public:

  /**
   Construct new instrument zone from entity in file.

   @param gens the vector of generators that define the zone
   @param mods the vector of modulators that define the zone
   @param sampleHeaders the collection of SHDR entities from the SF2 file
   */
  Instrument(GeneratorCollection&& gens, ModulatorCollection&& mods,
             const IO::ChunkItems<Entity::SampleHeader>& sampleHeaders) noexcept;

  /// @returns the original SHDR entity for this instrument zone as found in the SF2 file.
  inline const Entity::SampleHeader* sampleHeader() const noexcept { return sampleHeader_; }

  /// @returns the sample buffer registered to this zone. Throws exception if zone is global
  const NormalizedSamples& samples() const;

  /**
   Apply the instrument zone to the given voice state. Sets the nominal value of the generators in the zone.

   @param state the voice state to update
   */
  void apply(Voice::State::State& state) const noexcept;

  /**
   Install a `NormalizedSamples` object into this instrument to use for audio rendering.

   @param samples container holding the normalized floating-point samples to use for rendering.
   */
  void setNormalizedSamples(NormalizedSamples* samples) noexcept { samples_.reset(samples); }

private:
  const Entity::SampleHeader* sampleHeader_;
  std::unique_ptr<NormalizedSamples> samples_{nullptr};
};

} // namespace SF2::Render
