// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>

#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2::Render::Voice::State;

void
State::prepareForVoice(const Config& config) noexcept
{
  setDefaults();
  config.apply(*this);
  eventKey_ = config.eventKey();
  eventVelocity_ = config.eventVelocity();
}

void
State::setDefaults() noexcept {
  gens_.zero();
  setValue(Index::initialFilterCutoff, 13500);
  setValue(Index::delayModulatorLFO, -12000);
  setValue(Index::delayVibratoLFO, -12000);
  setValue(Index::delayModulatorEnvelope, -12000);
  setValue(Index::attackModulatorEnvelope, -12000);
  setValue(Index::holdModulatorEnvelope, -12000);
  setValue(Index::decayModulatorEnvelope, -12000);
  setValue(Index::releaseModulatorEnvelope, -12000);
  setValue(Index::delayVolumeEnvelope, -12000);
  setValue(Index::attackVolumeEnvelope, -12000);
  setValue(Index::holdVolumeEnvelope, -12000);
  setValue(Index::decayVolumeEnvelope, -12000);
  setValue(Index::releaseVolumeEnvelope, -12000);
  setValue(Index::forcedMIDIKey, -1);
  setValue(Index::forcedMIDIVelocity, -1);
  setValue(Index::scaleTuning, 100);
  setValue(Index::overridingRootKey, -1);

  // Install default modulators for the voice. Zones can override them and add new ones.
  modulators_.clear();
  for (const auto& modulator : Entity::Modulator::Modulator::defaults) {
    addModulator(modulator);
  }

  updateStateMods();
}

void
State::addModulator(const Entity::Modulator::Modulator& modulator) noexcept {
  if (!modulator.source().isValid()) return;

  // Per spec, there must only be one modulator with specific <sfModSrcOper, sfModDestOper, and sfModSrcAmtOper>
  // values. If we find a duplicate, then we update it's amount with the amount taken from the newer modulator.
  for (auto& mod : modulators_) {
    if (mod.configuration() == modulator) {
      mod.takeAmountFrom(modulator);
      return;
    }
  }

  // Add modulator to State and add its index to the GenValue instance that it affects.
  modulators_.emplace_back(modulator, *this);
}
