// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <iostream>
#include <sstream>

#include "SF2Lib/IO/Pos.hpp"
#include "SF2Lib/Entity/Modulator/Modulator.hpp"

using namespace SF2::Entity::Modulator;

const std::array<Modulator, Modulator::DefaultsSize> Modulator::defaults {
  // MIDI key velocity to initial attenuation (8.4.1)
  Modulator(Source(Source::GeneralIndex::noteOnVelocity).negative().concave(), Generator::Index::initialAttenuation,
            960),
  // MIDI key velocity to initial filter cutoff (8.4.2)
  Modulator(Source(Source::GeneralIndex::noteOnVelocity).negative().linear(), Generator::Index::initialFilterCutoff,
            -2400),
  // MIDI channel pressure to vibrato LFO pitch depth (8.4.3)
  Modulator(Source(Source::GeneralIndex::channelPressure).linear(), Generator::Index::vibratoLFOToPitch, 50),
  // MIDI CC 1 to vibrato LFO pitch depth (8.4.4)
  Modulator(Source(Source::CC(1)).linear(), Generator::Index::vibratoLFOToPitch, 50),
  // MIDI CC 7 to initial attenuation (NOTE spec says Source(0x0582) which gives CC 2) (8.4.5)
  Modulator(Source(Source::CC(7)).negative().concave(), Generator::Index::initialAttenuation, 960),
  // MIDI CC 10 to pan position (8.4.6)
  Modulator(Source(Source::CC(10)).bipolar().linear(), Generator::Index::pan, 500),
  // MIDI CC 11 to initial attenuation (8.4.7)
  Modulator(Source(Source::CC(11)).negative().concave(), Generator::Index::initialAttenuation, 960),
  // MIDI CC 91 to reverb amount (8.4.8)
  Modulator(Source(Source::CC(91)), Generator::Index::reverbEffectSend, 200),
  // MIDI CC 93 to chorus amount (8.4.9)
  Modulator(Source(Source::CC(93)), Generator::Index::chorusEffectSend, 200),
  // MIDI pitch wheel to "initial pitch" (8.4.10). Follow FluidSynth here: as there is no "initial pitch" generator in
  // the spec, link the modulator to `fineTune` instead. That way it can be overridden by a preset and/or instrument.
  Modulator(Source(Source::GeneralIndex::pitchWheel).bipolar().linear(),
            Generator::Index::fineTune, 12700,
            Source(Source::GeneralIndex::pitchWheelSensitivity))
};

Modulator::Modulator(IO::Pos& pos) noexcept
{
  pos = pos.readInto(*this);
}

Modulator::Modulator(Source modSrcOper, Generator::Index dest, int16_t amount, Source modAmtSrcOper,
                     Transformer transform) noexcept :
sfModSrcOper{modSrcOper},
sfModDestOper{static_cast<uint16_t>(dest)},
modAmount{amount},
sfModAmtSrcOper{modAmtSrcOper},
sfModTransOper{transform}
{
  ;
}

void
Modulator::dump(const std::string& indent, size_t index) const noexcept
{
  std::cout << indent << '[' << index << "] " << description() << std::endl;
}

std::string
Modulator::description() const noexcept
{
  std::ostringstream os;
  os << "Sv: " << sfModSrcOper << " Av: " << sfModAmtSrcOper << " dest: ";
  os << Generator::Definition::definition(generatorDestination()).name();

  os << " amount: " << modAmount << " trans: " << transformer();
  
  return os.str();
}
