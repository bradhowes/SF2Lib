// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "DSPHeaders/Types.hpp"
#include "SF2File/Entity/Generator/Definition.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"

using namespace SF2::MIDI;

void
ChannelState::reset() noexcept
{
  continuousControllerValues_.zero();

  // Follow settings from FluidSynth
  setContinuousControllerValue(ControlChange::volumeMSB, 100); // 7
  setContinuousControllerValue(ControlChange::balanceMSB, 64); // 8
  setContinuousControllerValue(ControlChange::panMSB, 64); // 10

  setContinuousControllerValue(ControlChange::expressionMSB, 127); // 11
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
  pitchWheelValue_ = (maxPitchWheelValue + 1) / 2; // This is the middle of the wheel at rest
  pitchWheelSensitivity_ = 2; // This should resolve to 200 cents
  nrpnIndex_ = 0;
  rpnSelected_ = false;

  pedalState_ = {false, false, false};
}

void
ChannelState::applyRPNDataEntry(uint8_t value) noexcept
{
  auto msb = continuousControllerValues_[ControlChange::rpnMSB];
  auto lsb = continuousControllerValues_[ControlChange::rpnLSB];

  // RPN 0 (MSB 0, LSB 0) is pitch bend sensitivity. The Data Entry MSB is the range in semitones, which is the value of
  // the SF2.01 "pitch wheel sensitivity" modulator source (8.2.1, index 16). The Data Entry LSB holds additional cents;
  // the modulator source only has semitone resolution, so it is ignored.
  if (msb == 0 && lsb == 0) {
    pitchWheelSensitivity_ = value & 0x7F;
  }
}

bool
ChannelState::decodeNRPN(MIDI::ControlChange cc, uint8_t value) noexcept
{
  switch (cc) {
    case MIDI::ControlChange::nrpnMSB:

      // The NRPN Select MSB message value is 120. This message indicates that a NRPN Message that follows will be a
      // SoundFont 2.01 NRPN message.
      activeDecoding_ = value == 120;
      nrpnIndex_ = 0;
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
          } else {
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

    case MIDI::ControlChange::dataEntryLSB:
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
      break;

      // Data Entry values are ONLY applied as SoundFont 2.01 controllers if and only if the most recently sent
      // NRPN MSB and LSB message comprises a SoundFont 2.01 message AND an RPN LSB/MSB message combination was NOT sent
      // more recently than the SoundFont 2.01 NRPN LSB/MSB message.
    case MIDI::ControlChange::rpnLSB:
    case MIDI::ControlChange::rpnMSB:
      activeDecoding_ = false;
      nrpnIndex_ = 0;
      break;

    default:
      // SF2.01 9.6.2: CC 99 (NRPN MSB) puts the synthesizer in NRPN Data Entry mode and CC 101 (RPN MSB) in RPN mode.
      // Other controllers do not change the mode, so a CC (e.g. the mod wheel or a pedal) sent between the NRPN select
      // and its Data Entry must not cancel it. (This used to clear `activeDecoding_`.)
      break;
  }

  return false;
}

void
ChannelState::resetControllers() noexcept
{
  // MIDI RP-015 "Response to Reset All Controllers". Reset these:
  continuousControllerValues_[ControlChange::modulationWheelMSB] = 0;
  continuousControllerValues_[ControlChange::modulationWheelLSB] = 0;
  continuousControllerValues_[ControlChange::expressionMSB] = 127;
  continuousControllerValues_[ControlChange::expressionLSB] = 127;
  for (auto cc : {ControlChange::sustainSwitch, ControlChange::portamentoSwitch, ControlChange::sostenutoSwitch,
                  ControlChange::softPedalSwitch}) {
    continuousControllerValues_[cc] = 0;
  }
  pedalState_ = {false, false, false};

  // RPN and NRPN numbers go to "null", so a following Data Entry does nothing.
  continuousControllerValues_[ControlChange::nrpnLSB] = 127;
  continuousControllerValues_[ControlChange::nrpnMSB] = 127;
  continuousControllerValues_[ControlChange::rpnLSB] = 127;
  continuousControllerValues_[ControlChange::rpnMSB] = 127;
  activeDecoding_ = false;
  rpnSelected_ = false;
  nrpnIndex_ = 0;

  pitchWheelValue_ = (maxPitchWheelValue + 1) / 2;
  channelPressure_ = 0;
  notePressureValues_.fill(0);

  // Do NOT reset: bank select, volume, pan, sound controllers (70-79), effects depths (91-95), or RPN/NRPN *values*
  // (pitch wheel sensitivity and the SF2 NRPN generator offsets in `nrpnValues_`).
  //
  // Controllers that RP-015 lists in neither group are left unchanged as well: 2-5, 8-9, 12-31, the LSBs 33-63 other
  // than those reset above, Legato (68), Hold 2 (69), 80-90, data increment/decrement (96-97) and 102-119. RP-015
  // permits a receiver to document such behaviour. Resetting them to 0 could be harmful (for instance, balance CC 8
  // defaults to 64), and none of them drives a default SF2 modulator.
}

bool
ChannelState::setContinuousControllerValue(MIDI::ControlChange cc, uint8_t value) noexcept
{
  if (decodeNRPN(cc, value)) return true;

  continuousControllerValues_[cc] = value;

  switch (cc) {
    case ControlChange::rpnMSB:
    case ControlChange::rpnLSB:
      // Selecting an RPN deselects any NRPN. 127/127 is the "RPN null" value, which deselects everything.
      rpnSelected_ = !(continuousControllerValues_[ControlChange::rpnMSB] == 127 &&
                       continuousControllerValues_[ControlChange::rpnLSB] == 127);
      break;

    case ControlChange::nrpnMSB:
    case ControlChange::nrpnLSB:
      rpnSelected_ = false;
      break;

    case ControlChange::dataEntryMSB:
      if (rpnSelected_) applyRPNDataEntry(value);
      break;

    case ControlChange::sustainSwitch:
      pedalState_.sustainPedalActive = value >= 64;
      break;

    case ControlChange::sostenutoSwitch:
      pedalState_.sostenutoPedalActive = value >= 64;
      break;

    case ControlChange::softPedalSwitch:
      pedalState_.softPedalActive = value >= 64;
      break;

    default:
      break;
  }

  return true;
}

void
ChannelState::dump() const noexcept
{
  for (size_t index = 0; index < 128; ++index) {
    std::cout << "CC " << index << " = " << continuousControllerValues_[index] << '\n';
  }
  for (auto pos = Entity::Generator::IndexIterator::begin(); pos != Entity::Generator::IndexIterator::end(); ++pos) {
    std::cout << "NRPN " << DSPHeaders::valueOf(*pos) << " = " << nrpnValues_[*pos] << '\n';
  }
}
