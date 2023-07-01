// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>

#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"

using namespace SF2::MIDI;

void
ChannelState::setContinuousControllerValue(MIDI::ControlChange cc, int value) noexcept
{
  assert(static_cast<int>(cc) >= CCMin && static_cast<int>(cc) <= CCMax);
  continuousControllerValues_[static_cast<size_t>(cc) - CCMin] = value;

  switch (cc) {
    case MIDI::ControlChange::nrpnMSB:
      activeDecoding_ = value == 120;
      nrpnIndex_ = 0;
      break;

    case MIDI::ControlChange::nrpnLSB:

      // According to SF2.01 spec, generator index values can be built up using special encoded values of the LSB.
      // Right now, the max generator defined is index 58 (overridingRootKey). I highly doubt there will be an expansion
      // which will get us above 100 much less 1k or 10k.
      if (value < 100) nrpnIndex_ += size_t(value);
      else if (value == 100) nrpnIndex_ += 100;
      else if (value == 101) nrpnIndex_ += 1000;
      else if (value == 102) nrpnIndex_ += 10000;
      break;

    case MIDI::ControlChange::dataEntryMSB:

      // We set new values when we see an MSB value. The LSB value comes from the current channel state.
      if (activeDecoding_) {
        if (nrpnIndex_ < nrpnValues_.size()) {
          Entity::Generator::Index index{nrpnIndex_};
          auto msb = ((0x7F & value) << 7);
          auto lsb = 0x7F & continuousControllerValues_[static_cast<int>(MIDI::ControlChange::dataEntryLSB)];
          auto factor = Entity::Generator::Definition::definition(index).nrpnMultiplier();
          auto maxValue = 8192;
          nrpnValues_[index] = std::clamp<int>(((msb | lsb) - maxValue), -maxValue, maxValue) * factor;
        }
        nrpnIndex_ = 0;
      }
      break;

    case MIDI::ControlChange::dataEntryLSB:
      break;

    case MIDI::ControlChange::rpnLSB:
    case MIDI::ControlChange::rpnMSB:
      activeDecoding_ = false;
      break;

    default:
      break;
  }
}
