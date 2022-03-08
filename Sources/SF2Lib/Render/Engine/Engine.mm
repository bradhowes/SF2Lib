// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Engine/Engine.hpp"

using namespace SF2::Render::Engine;

void
Engine::doMIDIEvent(const AUMIDIEvent& midiEvent)
{
  if (midiEvent.eventType != AURenderEventMIDI || midiEvent.length < 1) return;
  switch (midiEvent.data[0] & 0xF0) {

    case MIDI::CoreEvent::noteOff:
      if (midiEvent.length == 2) {
        noteOff(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::noteOn:
      if (midiEvent.length == 3) {
        noteOn(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::keyPressure:
      if (midiEvent.length == 3) {
        channelState_.setKeyPressure(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::controlChange:
      if (midiEvent.length == 3) {
        channelState_.setContinuousControllerValue(midiEvent.data[1], midiEvent.data[2]);
        nrpn_.process(midiEvent.data[1], midiEvent.data[2]);
      }
      break;

    case MIDI::CoreEvent::programChange:
      break;

    case MIDI::CoreEvent::channelPressure:
      if (midiEvent.length == 2) {
        channelState_.setChannelPressure(midiEvent.data[1]);
      }
      break;

    case MIDI::CoreEvent::pitchBend:
      if (midiEvent.length == 3) {
        int bend = (midiEvent.data[2] << 7) | midiEvent.data[1];
        channelState_.setPitchWheelValue(bend);
      }
      break;

    case MIDI::CoreEvent::reset:
      allOff();
      break;
  }
}
