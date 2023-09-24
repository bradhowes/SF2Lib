// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

namespace SF2::Render::Zone {
class Instrument;
class Preset;

}

namespace SF2::Render::Voice::Sample {
class NormalizedSampleSource;
}

namespace SF2::Render::Voice::State {

class State;

/**
 A combination of preset zone and instrument zone (plus optional global zones for each) that pertains to a MIDI
 key/velocity pair. One instance represents the configuration that should apply to the state of one voice for rendering
 samples at a specific key frequency and velocity.
 */
class Config {
public:

  /**
   Construct a preset/instrument pair

   @param preset the PresetZone that matched a key/velocity search
   @param globalPreset the global PresetZone to apply (optional -- nullptr if no global)
   @param instrument the InstrumentZone that matched a key/velocity search
   @param globalInstrument the global InstrumentZone to apply (optional -- nullptr if no global)
   @param eventKey the MIDI key that triggered the rendering
   @param eventVelocity the MIDI velocity that triggered the rendering
   */
  Config(const Zone::Preset& preset, const Zone::Preset* globalPreset, const Zone::Instrument& instrument,
         const Zone::Instrument* globalInstrument, int eventKey, int eventVelocity) noexcept;

  /// @returns the buffer of audio samples to use for rendering
  const Sample::NormalizedSampleSource& sampleSource() const noexcept;

  /// @returns original MIDI key that triggered the voice
  int eventKey() const noexcept { return eventKey_; }

  /// @returns original MIDI velocity that triggered the voice
  int eventVelocity() const noexcept { return eventVelocity_; }

  /// @returns value of `exclusiveClass` generator for an instrument if it is set, or 0 if not found.
  int exclusiveClass() const noexcept { return exclusiveClass_; }

private:

  /**
   Update a state with the various zone configurations. This is done once during the initialization of a Voice with a
   Config instance.

   @param state the voice state to update
   */
  void apply(State& state) const noexcept;

  const Zone::Preset& preset_;
  const Zone::Preset* globalPreset_;
  const Zone::Instrument& instrument_;
  const Zone::Instrument* globalInstrument_;
  int eventKey_;
  int eventVelocity_;
  int exclusiveClass_;

  friend State;  /// Grant access to `apply`.
};

} // namespace SF2::Render
