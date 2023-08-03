// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <map>

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/MIDI/Note.hpp"

/**
 Collection of enums and types used to represent MIDI v1 values and state.
 */
namespace SF2::MIDI {

enum struct CoreEvent {
  noteOff = 0x80,
  noteOn = 0x90,
  keyPressure = 0xA0,
  controlChange = 0xB0,
  programChange = 0xC0,
  channelPressure = 0xD0,
  pitchBend = 0xE0,
  systemExclusive = 0xF0,
  timeCodeQuarterFrame = 0xF1,
  songPositionPointer = 0xF2,
  songSelect = 0xF3,
  undefined1 = 0xF4,
  undefined2 = 0xF5,
  tuneRequest = 0xF6,
  EOX = 0xF7,
  timingClock = 0xF8,
  undefined3 = 0xF9,
  undefined4 = 0xFD,
  reset = 0xFF
};

enum struct ControlChange {
  bankSelectMSB = 0x00,
  modulationWheelMSB = 0x01,
  breathMSB = 0x02,
  footMSB = 0x04,
  portamentoTimeMSB = 0x05,
  dataEntryMSB = 0x06,
  volumeMSB = 0x07,
  balanceMSB = 0x08,
  panMSB = 0x0A,
  expressionMSB = 0x0B,
  effects1MSB = 0x0C,
  effects2MSB = 0x0D,

  generalPurpose1MSB = 0x10,
  generalPurpose2MSB = 0x11,
  generalPurpose3MSB = 0x12,
  generalPurpose4MSB = 0x13,

  bankSelectLSB = 0x20,
  modulationWheelLSB = 0x21,
  breathLSB = 0x22,
  footLSB = 0x24,
  portamentoTimeLSB = 0x25,
  dataEntryLSB = 0x26,
  volumeLSB = 0x27,
  balanceLSB = 0x28,
  panLSB = 0x2A,
  expressionLSB = 0x2B,
  effects1LSB = 0x2C,
  effects2LSB = 0x2D,

  generalPurpose1LSB = 0x30,
  generalPurpose2LSB = 0x31,
  generalPurpose3LSB = 0x32,
  generalPurpose4LSB = 0x33,

  sustainSwitch = 0x40,
  portamentoSwitch = 0x41,
  sostenutoSwitch = 0x42,
  softPedalSwitch = 0x43,
  legatoSwitch = 0x44,
  hold2Switch = 0x45,

  soundControl1 = 0x46,
  soundControl2 = 0x47,
  soundControl3 = 0x48,
  soundControl4 = 0x49,
  soundControl5 = 0x4A,
  soundControl6 = 0x4B,
  soundControl7 = 0x4C,
  soundControl8 = 0x4D,
  soundControl9 = 0x4E,
  soundControl10 = 0x4F,

  generalPurpose5 = 0x50,
  generalPurpose6 = 0x51,
  generalPurpose7 = 0x52,
  generalPurpose8 = 0x53,

  portamentoControl = 0x54,
  effectsDepth1 = 0x5B,
  effectsDepth2 = 0x5C,
  effectsDepth3 = 0x5D,
  effectsDepth4 = 0x5E,
  effectsDepth5 = 0x5F,

  dataEntryIncrement = 0x60,
  dataEntryDecrement = 0x61,

  nrpnLSB = 0x62,
  nrpnMSB = 0x63,
  rpnLSB = 0x64,
  rpnMSB = 0x65,

  // Channel messages
  allSoundOff = 0x78,
  resetAllControllers = 0x79,
  localControl = 0x7A,
  allNotesOff = 0x7B,
  omniOff = 0x7C,
  omniOn = 0x7D,
  monoOn = 0x7E,
  polyOn = 0x7F
};

/* General MIDI RPN event numbers (LSB, MSB = 0) */
enum struct RPNEvent
{
  pitchBendRange = 0x00,
  channelFineTune = 0x01,
  channelCoarseTune = 0x02,
  tuningProgramChange = 0x03,
  tuningBankSelect = 0x04,
  modulationDepthRange = 0x05
};

} // namespace SF2::MIDI
