// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"
#include "SF2Lib/MIDI/NRPN.hpp"

using namespace SF2::MIDI;

void
NRPN::process(int cc, int value)
{
  switch (cc) {
    case MIDI::ControlChange::nprnMSB:
      active_ = value == 120;
      index_ = 0;
      break;

    case MIDI::ControlChange::nprnLSB:

      // According to SF2.01 spec, generator index values can be built up using special encoded values of the LSB.
      // Right now, the max generator defined is index 58 (overridingRootKey). I highly doubt there will be an expansion
      // which will get us above 100 much less 1k or 10k.
      if (value < 100) index_ += value;
      else if (value == 100) index_ += 100;
      else if (value == 101) index_ += 1000;
      else if (value == 102) index_ += 10000;
      break;

    case MIDI::ControlChange::dataEntryMSB:

      // We set new values when we see an MSB value.
      if (active_) {
        if (index_ < nrpnValues_.size()) {
          auto msb = (value << 7);
          auto lsb = channelState_.continuousControllerValue(MIDI::ControlChange::dataEntryLSB);
          auto factor = Entity::Generator::Definition::definition(Entity::Generator::Index(index_)).nrpnMultiplier();
          auto maxValue = 8192; // signed 13-bit value.
          nrpnValues_[index_] = DSP::clamp(((msb + lsb) - maxValue), -maxValue, maxValue) * factor;
        }
        index_ = 0;
      }
      break;

    case MIDI::ControlChange::dataEntryLSB:
      break;

    case MIDI::ControlChange::rpnLSB:
    case MIDI::ControlChange::rpnMSB:
      active_ = false;
      break;
  }
}
