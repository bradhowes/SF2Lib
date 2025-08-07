# Modulator Namespace

Contains definitions for SF2 modulators. Modulators allow MIDI controllers and keys to affect SF2 generators by adding
scaled values to the values defined in a SoundFont file.

## Implemented Modulators

The following are the modulators somewhat defined in the SF2 spec. See [Modulator.mm](Modulator.mm) for details.

* MIDI key velocity to initial attenuation (8.4.1)
* MIDI key velocity to initial filter cutoff (8.4.2)
* MIDI channel pressure to vibrato LFO pitch depth (8.4.3)
* MIDI CC 1 to vibrato LFO pitch depth (8.4.4)
* MIDI CC 7 to initial attenuation (NOTE spec says Source(0x0582) which gives CC 2) (8.4.5)
* MIDI CC 10 to pan position (8.4.6)
* MIDI CC 11 to initial attenuation (8.4.7)
* MIDI CC 91 to reverb amount (8.4.8)
* MIDI CC 93 to chorus amount (8.4.9)
* MIDI pitch wheel to "initial pitch" (8.4.10). Follow FluidSynth here: as there is no "initial pitch" generator in
  the spec, link the modulator to `fineTune` instead. That way it can be overridden by a preset and/or instrument.

Additional modulators can be defined by an SF2 file, and the SF2Lib Engine will attempt to honor them. However, the 
spec does not require this -- it only requires being able to override or disable a modulation from the SF2 file
definition.
