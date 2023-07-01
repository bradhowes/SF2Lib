// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Utils/Base64.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/IO/File.hpp"

using namespace SF2::Render::Engine;

void
Engine::doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept
{
  switch (MIDI::CoreEvent(midiEvent.data[0] & 0xF0)) {

    case MIDI::CoreEvent::noteOff:
      os_log_info(log_, "doMIDIEvent - noteOff: %hhd", midiEvent.data[1]);
      if (midiEvent.length == 3) {
        noteOff(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::noteOn:
      os_log_info(log_, "doMIDIEvent - noteOn: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length == 3) {
        noteOn(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::keyPressure:
      os_log_info(log_, "doMIDIEvent - keyPressure: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length == 3) {
        channelState_.setNotePressure(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::controlChange:
      os_log_info(log_, "doMIDIEvent - controlChange: %hhX %hhX", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length == 3 && midiEvent.data[1] <= 127 && midiEvent.data[2] <= 127) {
        auto cc{MIDI::ControlChange(midiEvent.data[1])};
        channelState_.setContinuousControllerValue(cc, midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::programChange:
      os_log_info(log_, "doMIDIEvent - programChange: %hhd", midiEvent.data[1]);
      if (midiEvent.length == 2) {
        changeProgram(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::channelPressure:
      os_log_info(log_, "doMIDIEvent - channelPressure: %hhd", midiEvent.data[1]);
      if (midiEvent.length == 2) {
        channelState_.setChannelPressure(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::pitchBend:
      os_log_info(log_, "doMIDIEvent - pitchBend: %hhd %hhd", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length == 3) {
        int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
        channelState_.setPitchWheelValue(bend);
      }
      break;

      // System-Exclusive command for loading URL in SF2Engine:
      //
      //   0 0xF0 - System Exclusive
      //   1 0x7E - non-realtime ID
      //   2 0x00 - unused subtype
      //   3 0xAA - MSB of the preset to load
      //   4 0xBB - LSB of the preset to load
      //   5 ...  - N Base-64 encoded URL bytes
      // 5+N 0xF7 - EOX
      //
    case MIDI::CoreEvent::systemExclusive:
      os_log_info(log_, "doMIDIEvent - systemExclusive: %hhX %hhX", midiEvent.data[1], midiEvent.data[2]);
      if (midiEvent.length > 2 && midiEvent.data[1] == 0x7e && midiEvent.data[2] == 0x00) {
        loadFromMIDI(midiEvent);
      }
      break;

    case MIDI::CoreEvent::reset:
      os_log_info(log_, "doMIDIEvent - reset");
      allOff();
      break;

    default:
      break;
  }
}

void
Engine::processControlChange(MIDI::ControlChange cc) noexcept
{
  switch (cc) {
    case MIDI::ControlChange::bankSelectMSB:
      channelState_.setContinuousControllerValue(MIDI::ControlChange::bankSelectLSB, 0);
      break;
    default:
      break;
  }
}

void
Engine::loadFromMIDI(const AUMIDIEvent& midiEvent) noexcept {
  size_t count = midiEvent.length - 5;
  size_t index = (*(&midiEvent.data[0] + 3) * 256) + *(&midiEvent.data[0] + 4);
  auto path = Utils::Base64::decode(&midiEvent.data[0] + 5, count);
  os_log_info(log_, "loadFromMIDI BEGIN - %{public}s", path.c_str());
  SF2::IO::File file{path.c_str()};
  load(file, index);
}

void
Engine::changeProgram(int program) noexcept {
  int bank = channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectMSB) * 128 +
  channelState_.continuousControllerValue(MIDI::ControlChange::bankSelectLSB);
  usePreset(bank, program);
}
