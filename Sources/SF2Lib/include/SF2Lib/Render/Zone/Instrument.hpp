// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>

#include "SF2File/Entity/SampleHeader.hpp"
#include "SF2File/IO/ChunkItems.hpp"
#include "SF2Lib/Render/Zone/Zone.hpp"
#include "SF2Lib/Render/Zone/NormalizedSampleSpan.hpp"

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

  /// @returns the original 'shrd' entity for this instrument zone as found in the SF2 file if this is not a
  /// global zone. Otherwise, returns `nullptr`
  inline const Entity::SampleHeader* sampleHeader() const noexcept { return sampleHeader_; }

  /// @returns the sample buffer registered to this zone. Note that this must only be called if `sampleHeader()` returns non-null
  /// otherwise it throws an exception.
  std::shared_ptr<NormalizedSampleSpan> samples() const {
    if (sampleHeader_ == nullptr) throw std::runtime_error("global instrument zone has no sample source");
    if (!samples_) throw std::runtime_error("unexpected nil sample source");
    return samples_;
  }

  /**
   Apply the instrument zone to the given voice state. Sets the nominal value of the generators in the zone.

   @param state the voice state to update
   */
  void apply(Voice::State::State& state) const noexcept;

  /**
   Install the `NormalizedSampleSpan` to use for audio rendering.

   @param samples container holding normalized floating-point samples.
   */
  void setSamples(std::shared_ptr<NormalizedSampleSpan>&& samples) noexcept { samples_ = samples; }

  /**
   Stop using any previously-installed `NormalizedSampleSpan` value.
   */
  void releaseSamples() noexcept { samples_.reset(); }

private:
  const Entity::SampleHeader* sampleHeader_;
  std::shared_ptr<NormalizedSampleSpan> samples_{};
  inline static const os_log_t log_{Log::create("Zone::Instrument")};
};

} // namespace SF2::Render
