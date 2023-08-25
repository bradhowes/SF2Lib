// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Voice/Sample/NormalizedSampleSource.hpp"
#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/Zone/Preset.hpp"
#include "SF2Lib/Render/Zone/Instrument.hpp"

using namespace SF2::Render::Voice::State;

Config::Config(const Zone::Preset& preset, const Zone::Preset* globalPreset, const Zone::Instrument& instrument,
               const Zone::Instrument* globalInstrument, int eventKey, int eventVelocity) noexcept :
preset_{preset},
globalPreset_{globalPreset},
instrument_{instrument},
globalInstrument_{globalInstrument},
eventKey_{eventKey},
eventVelocity_{eventVelocity},
exclusiveClass_{0}
{
  for (const auto& box : instrument_.generators()) {
    const auto& gen{box.get()};
    if (gen.index() == Entity::Generator::Index::exclusiveClass) {
      exclusiveClass_ = gen.amount().unsignedAmount();
      break;
    }
  }
}

const SF2::Render::Voice::Sample::NormalizedSampleSource&
Config::sampleSource() const noexcept
{
  return instrument_.sampleSource();
}

void
Config::apply(State& state) const noexcept
{
  // Use Instrument zones to set absolute values. Do the global state first, then allow instruments to change
  // their settings.
  if (globalInstrument_ != nullptr) globalInstrument_->apply(state);
  instrument_.apply(state);

  // Presets apply refinements to absolute values set from instruments zones above.
  if (globalPreset_ != nullptr) globalPreset_->refine(state);
  preset_.refine(state);
}
