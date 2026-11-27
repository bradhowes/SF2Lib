// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Render/Envelope/Generator.hpp"

/**
 Representation of an envelope with various stages that have their own timing characteristics and levels.

 The SF2 spec implies that the envelopes are to be thought of as representing an attenuation value
 where the peak is 0 dB attenuation and the floor is -100dB (regardless of bit count of the samples).
 This implementation instead treats the envelope as a value from 0.0 (floor) to 1.0 (peak).
 */
namespace SF2::Render::Envelope {

class Volume : public Generator
{
public:
  /**
   Type-specific wrapper for envelope value to help ensure proper use of the right value in signal flows.
   */
  struct Value {
    const Float val;
  };

  /**
   Create a volume envelope for a voice
   */
  Volume() noexcept : Generator("VolGen") { enableConvexAttack(); }

  /**
   Create new envelope for volume changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  void configure(const State& state) noexcept { configureVolumeEnvelope(state); }

  /// @returns the current envelope value.
  Value value() const noexcept { return {Generator::value()}; }

  /**
   Calculate the next envelope value. This must be called on every sample for proper timing of the stages.

   @returns the new envelope value.
   */
  Value getNextValue() noexcept { return {Generator::getNextValue()}; }

  /// @returns the amplitude fraction (0 to 1) of the attack curve, valid while `activeIndex()` is the attack stage
  Float attackAmplitude() const noexcept { return attackProgress(); }

  /**
   Calculate the next `count` envelope values, exactly as `count` calls to `getNextValue` would (see
   `Generator::fillBlock`).

   @param values receives the envelope values
   @param stages receives the stage the envelope is in after each value
   @param count the number of values to generate
   */
  void fillBlock(Float* values, StageIndex* stages, size_t count) noexcept {
    Generator::fillBlock(values, stages, count);
  }

private:
  Volume(Float sampleRate, Float delay, Float attack, Float hold, Float decay, int sustain, Float release) noexcept :
  Generator(sampleRate, "VolGen", delay, attack, hold, decay, sustain, release) { enableConvexAttack(); }

  friend struct EnvelopeTestInjector;
};

} // namespace SF2::Render::Envelope
