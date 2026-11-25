// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "SF2File/IO/NormalizedSampleSource.hpp"
#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/Zone/NormalizedSampleSpan.hpp"
#include "SF2Lib/Render/Zone/Preset.hpp"
#include "SF2Lib/Render/Zone/Instrument.hpp"

using namespace SF2::Render::Voice::State;

Config::Config(const Zone::Preset &preset, const Zone::Preset *globalPreset,
               const Zone::Instrument &instrument,
               const Zone::Instrument *globalInstrument, int eventKey,
               int eventVelocity) noexcept
  : preset_{preset}, globalPreset_{globalPreset}, instrument_{instrument}, globalInstrument_{globalInstrument},
    eventKey_{eventKey}, eventVelocity_{eventVelocity}, exclusiveClass_{0}
{
  // Look for an exclusiveClass definition in the global instrument if there is one. Let a later definition override
  // an earlier one.
  if (globalInstrument) {
    for (const auto& box : globalInstrument->generators()) {
      const auto& gen{box.get()};
      if (gen.index() == Entity::Generator::Index::exclusiveClass) {
        exclusiveClass_ = gen.amount().unsignedAmount();
      }
    }
  }

  // Look for an exclusiveClass definition in the instrument. Let a later definition override
  // an earlier one as well as any found in a global instrument.
  for (const auto& box : instrument_.generators()) {
    const auto& gen{box.get()};
    if (gen.index() == Entity::Generator::Index::exclusiveClass) {
      exclusiveClass_ = gen.amount().unsignedAmount();
    }
  }
}

void
Config::applyTo(State& state) const noexcept
{
  // Use Instrument zones to set absolute values. Do the global state first, then allow instruments to change
  // their settings.
  if (globalInstrument_ != nullptr) state.configureWith(*globalInstrument_);
  state.configureWith(instrument_);

  // Presets apply refinements to absolute values set from instruments zones above.
  if (globalPreset_ != nullptr) state.configureWith(*globalPreset_);
  state.configureWith(preset_);

  // Preset modulators add to the instrument (and default) modulators installed above.
  state.addPresetModulators(globalPreset_, preset_);
}
