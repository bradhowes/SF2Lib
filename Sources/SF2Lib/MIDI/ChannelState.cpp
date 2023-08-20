// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>

#include "SF2Lib/Entity/Generator/Definition.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"

using namespace SF2::MIDI;

void
ChannelState::reset() noexcept
{
  continuousControllerValues_.fill(0);

  // Follow settings from FluidSynth
  setContinuousControllerValue(ControlChange::volumeMSB, 100);
  setContinuousControllerValue(ControlChange::balanceMSB, 64);
  setContinuousControllerValue(ControlChange::panMSB, 64);

  setContinuousControllerValue(ControlChange::expressionMSB, 127);
  setContinuousControllerValue(ControlChange::expressionLSB, 127);

  setContinuousControllerValue(ControlChange::soundControl1, 64);
  setContinuousControllerValue(ControlChange::soundControl2, 64);
  setContinuousControllerValue(ControlChange::soundControl3, 64);
  setContinuousControllerValue(ControlChange::soundControl4, 64);
  setContinuousControllerValue(ControlChange::soundControl5, 64);
  setContinuousControllerValue(ControlChange::soundControl6, 64);
  setContinuousControllerValue(ControlChange::soundControl7, 64);
  setContinuousControllerValue(ControlChange::soundControl8, 64);
  setContinuousControllerValue(ControlChange::soundControl9, 64);
  setContinuousControllerValue(ControlChange::soundControl10, 64);

  continuousControllerValues_[ControlChange::nrpnLSB] = 127;
  continuousControllerValues_[ControlChange::nrpnMSB] = 127;
  continuousControllerValues_[ControlChange::rpnLSB] = 127;
  continuousControllerValues_[ControlChange::rpnMSB] = 127;

  notePressureValues_.fill(0);

  nrpnValues_.zero();
  channelPressure_ = 0;
  pitchWheelValue_ = (maxPitchWheelValue + 1) / 2; // this is the middle of the wheel at rest
  pitchWheelSensitivity_ = 200;
  nrpnIndex_ = 0;

  sustainActive_ = false;
  sostenutoActive_ = false;
  activeDecoding_ = false;
}

bool
ChannelState::setContinuousControllerValue(MIDI::ControlChange cc, int value) noexcept
{
  continuousControllerValues_[cc] = value;

  switch (cc) {
    case MIDI::ControlChange::nrpnMSB:

      // The NRPN Select MSB message value is 120. This message indicates that a NRPN Message that follows will be a
      // SoundFont 2.01 NRPN message.
      activeDecoding_ = value == 120;
      nrpnIndex_ = 0;
      break;

    case MIDI::ControlChange::dataEntryLSB:
      break;

    case MIDI::ControlChange::nrpnLSB:
      if (activeDecoding_) {
        // According to SF2.01 spec, generator index values can be built up using special encoded values of the LSB.
        // Right now, the max generator defined is index 58 (overridingRootKey). I highly doubt there will be an
        // expansion which will get us above 100 much less 1k or 10k...
        if (value < 100) {

          // Section 9.6.2:
          //
          // The NRPN Select LSB message with data less than 100 corresponds to the generator enumeration value,
          // modulo 100, if and only if the most recently sent NRPN Select MSB message was 120. The NRPN Select LSB
          // message with data greater than or equal to 100 is used to permit selecting of generator values greater than
          // 100.
          //
          // Running status does not include multiple sends of values greater than 100. IE you cannot use a single
          // message to select 251 if the most recently sent message selected generator 250.
          if (nrpnIndex_ % 100) {
            nrpnIndex_ = size_t(value);
          }
          else {
            nrpnIndex_ += size_t(value);
          }
        }
        // Unclear from spec LSB 8, LSB 100 should be treated as 108 or as 100. We will go with the former, and allow
        // any ordering of large multiples up until we have a final value < 100.
        else if (value == 100) nrpnIndex_ += 100;
        else if (value == 101) nrpnIndex_ += 1000;
        else if (value == 102) nrpnIndex_ += 10000;
      }
      break;

    case MIDI::ControlChange::dataEntryMSB:

      // We set new values when we see an MSB value. The LSB value comes from the current channel state.
      if (activeDecoding_) {
        if (nrpnIndex_ < nrpnValues_.size()) {
          auto index = Entity::Generator::Index(nrpnIndex_);
          auto msb = ((0x7F & value) << 7);
          auto lsb = 0x7F & checkedVectorIndexing(continuousControllerValues_,
                                                  static_cast<size_t>(MIDI::ControlChange::dataEntryLSB));
          auto factor = Entity::Generator::Definition::definition(index).nrpnMultiplier();
          auto modValue = ((msb | lsb) - 8192) * factor;
          nrpnValues_[index] = modValue;
          return true;
        }
      }
      DISPATCH_FALLTHROUGH;

    // Data Entry values are ONLY applied as SoundFont 2.01 controllers if and only if the most recently sent
    // NRPN MSB and LSB message comprises a SoundFont 2.01 message AND an RPN LSB/MSB message combination was NOT sent
    // more recently than the SoundFont 2.01 NRPN LSB/MSB message.
    case MIDI::ControlChange::rpnLSB:
    case MIDI::ControlChange::rpnMSB:
      DISPATCH_FALLTHROUGH;

    default:
      activeDecoding_ = false;
      nrpnIndex_ = 0;
      break;
  }

  return !activeDecoding_;
}
