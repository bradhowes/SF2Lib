// Copyright © 2022, 2025, 2026 Brad Howes. All rights reserved.

#pragma once

#include <cstddef>
#include <memory>

#include "SF2Lib/Render/Zone/Instrument.hpp"

namespace SF2::Entity { class SampleHeader; }

namespace SF2::Render::Zone {
class NormalizedSampleSpan;
class Preset;
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
  std::shared_ptr<Zone::NormalizedSampleSpan> samples() const noexcept { return instrument_.samples(); }

  /// @returns original MIDI key that triggered the voice
  int eventKey() const noexcept { return eventKey_; }

  /// @returns original MIDI velocity that triggered the voice
  int eventVelocity() const noexcept { return eventVelocity_; }

  /// @returns value of `exclusiveClass` generator for an instrument if it is set, or 0 if not found.
  int exclusiveClass() const noexcept { return exclusiveClass_; }

  /// @returns the sample header of the instrument zone
  const Entity::SampleHeader* sampleHeader() const noexcept { return instrument_.sampleHeader(); }

  /// @returns the index of the instrument zone's sample header in the SHDR chunk
  size_t sampleIndex() const noexcept { return instrument_.sampleIndex(); }

  /// @returns the preset zone that matched. Two configs from the same preset zone use the same instrument.
  const Zone::Preset* presetZone() const noexcept { return &preset_; }

  /**
   Determine if this config and another are the two halves of a stereo pair (SF2.01 7.10): this one plays a right
   sample and the other its left sample, both headers point to each other, and both come from the same preset zone (so
   the same instrument: "Left-right pairs should always be found within the same instrument").

   @param left the config to check as the left half
   @returns true if this config is the right half and `left` the left half of the same stereo pair
   */
  bool isStereoRightOf(const Config& left) const noexcept {
    auto rightHeader = sampleHeader();
    auto leftHeader = left.sampleHeader();
    if (rightHeader == nullptr || leftHeader == nullptr || presetZone() != left.presetZone()) return false;
    return rightHeader->isRight() && leftHeader->isLeft() &&
    rightHeader->sampleLinkIndex() == left.sampleIndex() && leftHeader->sampleLinkIndex() == sampleIndex();
  }

  /**
   Update a state with the various zone configurations. This is done once during the initialization of a Voice with a
   Config instance.

   @param state the voice state to update
   */
  void applyTo(State& state) const noexcept;

private:
  const Zone::Preset& preset_;
  const Zone::Preset* globalPreset_;
  const Zone::Instrument& instrument_;
  const Zone::Instrument* globalInstrument_;
  int eventKey_;
  int eventVelocity_;
  int exclusiveClass_;
};

} // namespace SF2::Render
