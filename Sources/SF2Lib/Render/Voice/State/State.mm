// Copyright © 2022 Brad Howes. All rights reserved.

#include <algorithm>
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
State::prepareForVoice(const Config& config, const MIDI::ChannelState& channelState) noexcept
{
  clear();
  config.applyTo(*this);
  eventKey_ = config.eventKey();
  eventVelocity_ = config.eventVelocity();
  updateStateMods(channelState);
}

namespace {

using ModulatorCollection = SF2::Render::Zone::Zone::ModulatorCollection;

/// @returns true if `mods[index]` is followed in the same zone by a modulator with the same three enumerators. SF2.01
/// 7.4: "If a second modulator is encountered with the same three enumerators as a previous modulator with the same
/// zone, the first modulator will be ignored." The transform is not one of the three.
bool isShadowed(const ModulatorCollection& mods, size_t index) noexcept {
  const auto& mod = mods[index].get();
  return std::any_of(mods.begin() + long(index) + 1, mods.end(), [&mod](const auto& other) {
    return other.get().hasSameEnumerators(mod);
  });
}

} // namespace

void
State::configureWith(const Zone::Instrument& instrument) noexcept {
  // Generator state settings
  std::for_each(instrument.generators().cbegin(), instrument.generators().cend(),
                [this](const Entity::Generator::Generator& generator) {
    if (generator.isValid()) setValue(generator.index(), generator.value());
  });

  // Modulator definitions. A modulator that is followed in the same zone by one with the same three enumerators is
  // ignored (7.4). `addModulator` then replaces an identical (9.5.1) default or global zone modulator.
  const auto& mods = instrument.modulators();
  for (size_t index = 0; index < mods.size(); ++index) {
    if (!isShadowed(mods, index)) addModulator(mods[index].get());
  }
}

void
State::configureWith(const Zone::Preset& preset) noexcept {
  std::for_each(preset.generators().cbegin(), preset.generators().cend(),
                [this](const Entity::Generator::Generator& generator) {
    if (generator.isValid() && generator.definition().isAvailableInPreset()) {
      setAdjustment(generator.index(), generator.value());
    }
  });
}

bool
State::isUsable(const Entity::Modulator::Modulator& modulator) noexcept {
  // SF2.01 8.2: modulators with an invalid source, amount source or destination are ignored. A destination with bit 15
  // set is a 2.04 modulator link, which is not supported, and would otherwise index past the end of `gens_`. Likewise
  // for an unknown transform (7.4, 10.3: "unknown enumerators should simply cause the associated Generator or Modulator
  // to be ignored").
  if (!modulator.source().isValid() || !modulator.amountSource().isValid()) return false;
  if (!modulator.transformer().isValid()) return false;
  return SF2::valueOf(modulator.generatorDestination()) < SF2::valueOf(Index::numValues);
}


void
State::addPresetModulators(const Zone::Preset* globalPreset, const Zone::Preset& preset) noexcept {
  const auto& localMods = preset.modulators();
  if (globalPreset != nullptr) {
    const auto& globalMods = globalPreset->modulators();
    for (size_t index = 0; index < globalMods.size(); ++index) {
      if (isShadowed(globalMods, index)) continue;
      // 9.5.1: "A modulator, contained within a local preset zone, that is identical to a modulator in a global preset
      // zone supersedes or replaces that modulator in the global preset zone."
      const auto& mod = globalMods[index].get();
      if (std::any_of(localMods.begin(), localMods.end(), [&mod](const auto& other) { return other.get() == mod; })) {
        continue;
      }
      addPresetModulator(mod);
    }
  }
  for (size_t index = 0; index < localMods.size(); ++index) {
    if (!isShadowed(localMods, index)) addPresetModulator(localMods[index].get());
  }
}

void
State::addPresetModulator(const Entity::Modulator::Modulator& modulator) noexcept {
  if (!isUsable(modulator)) return;
  // 9.5.1: "A modulator at the preset level adds to a modulator at the instrument level if both modulators are
  // identical. Otherwise, the effects of a modulator at the preset level are added to the effects of a modulator at
  // the instrument level." Default modulators count as instrument level here.
  for (auto& mod : modulators_) {
    if (mod.configuration() == modulator) {
      mod.addAmountFrom(modulator);
      return;
    }
  }
  modulators_.emplace_back(modulator);
}

void
State::addModulator(const Entity::Modulator::Modulator& modulator) noexcept {
  if (!isUsable(modulator)) return;

  // SF2.01 9.5.1: an identical modulator (same source, destination, amount source and transform) in a later level
  // supersedes an earlier one (default -> global instrument zone -> local instrument zone), so take its amount.
  // Duplicates within one zone have already been dropped by `isShadowed`.
  for (auto& mod : modulators_) {
    if (mod.configuration() == modulator) {
      mod.takeAmountFrom(modulator);
      return;
    }
  }
  modulators_.emplace_back(modulator);
}

void
State::updateStateMods(const MIDI::ChannelState& channelState) noexcept
{
  // Overwrite a generator's mods value with the NRPN value configured for it
  std::for_each(Entity::Generator::IndexIterator::begin(), Entity::Generator::IndexIterator::end(), [&](auto index) {
    auto value{channelState.nrpnValue(index)};
    if (value != 0 || value != gens_[index].mods()) {
      // std::cout << "setMod " << Definition::definition(index).name() << " = " << value << '\n';
      gens_[index].setMods(value);
    }
  });

  // Calculate modulator values and add to the existing generator's mods value.
  for (auto& mod : modulators_) {
    auto value{mod.value(*this, channelState)};
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
}
