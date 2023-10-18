// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"
#include "SF2Lib/Render/Zone/Instrument.hpp"
#include "SF2Lib/Render/Zone/Preset.hpp"

using namespace SF2::Render::Voice::State;

void
State::clear() noexcept
{
  // Reset all of the generators and apply default values.
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

  // Reinstall default modulators just in case a prior instrument config installed something
  modulators_.clear();
  for (const auto& modulator : Entity::Modulator::Modulator::defaults) {
    addModulator(modulator);
  }
}

void
State::prepareForVoice(const Config& config) noexcept
{
  clear();
  config.applyTo(*this);
  eventKey_ = config.eventKey();
  eventVelocity_ = config.eventVelocity();
  updateStateMods();
}

void
State::configureWith(const Zone::Instrument& instrument) noexcept {
  // Generator state settings
  std::for_each(instrument.generators().cbegin(), instrument.generators().cend(),
                [this](const Entity::Generator::Generator& generator) {
    setValue(generator.index(), generator.value());
  });

  // Modulator definitions
  std::for_each(instrument.modulators().cbegin(), instrument.modulators().cend(),
                [this](const Entity::Modulator::Modulator& modulator) {
    addModulator(modulator);
  });
}

void
State::configureWith(const Zone::Preset& preset) noexcept {
  std::for_each(preset.generators().cbegin(), preset.generators().cend(),
                [this](const Entity::Generator::Generator& generator) {
    if (generator.definition().isAvailableInPreset()) {
      setAdjustment(generator.index(), generator.value());
    }
  });
}

void
State::addModulator(const Entity::Modulator::Modulator& modulator) noexcept {
  if (!modulator.source().isValid()) return;

  // Per spec, there must only be one modulator with specific <sfModSrcOper, sfModDestOper, and sfModSrcAmtOper>
  // values. If we find a duplicate, then we just update it's amount with the amount taken from the newer modulator and
  // exit.
  for (auto& mod : modulators_) {
    if (mod.configuration() == modulator) {
      mod.takeAmountFrom(modulator);
      return;
    }
  }
  modulators_.emplace_back(modulator);
}

void
State::updateStateMods() noexcept
{
  // Overwrite a generator's mods value with the NRPN value configured for it
  std::for_each(Entity::Generator::IndexIterator::begin(), Entity::Generator::IndexIterator::end(), [&](auto index) {
    auto value{channelState_.nrpnValue(index)};
    if (value != 0 || value != gens_[index].mods()) {
      // std::cout << "setMod " << Definition::definition(index).name() << " = " << value << '\n';
      gens_[index].setMods(value);
    }
  });

  // Calculate modulator values and add to the existing generator's mods value.
  for (auto& mod : modulators_) {
    auto value{mod.value(*this)};
    if (value != 0) {
      // std::cout << "addMod " << Definition::definition(mod.destination()).name() << " += " << value << '\n';
      gens_[mod.destination()].addMod(value);
    }
  }

  // dump();
}

void
State::dump() noexcept
{
  for (auto pos = Entity::Generator::IndexIterator::begin(); pos != Entity::Generator::IndexIterator::end(); ++pos) {
    auto& gen{gens_[*pos]};
    std::cout << valueOf(*pos) << " value: " << gen.instrumentValue() << " adj: " << gen.presetValue()
    << " mods: " << gen.mods() << '\n';
  }
  for (auto& mod : modulators_) {
    std::cout << mod.description() << '\n';
  }
  channelState_.dump();
}
