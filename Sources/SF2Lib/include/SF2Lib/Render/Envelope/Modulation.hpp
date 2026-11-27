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

class Modulation : public Generator
{
public:
  /**
   Type-specific wrapper for envelope value to help ensure proper use of the right value in signal flows.
   */
  struct Value {
    const Float val;
  };

  /**
   Create a modulation envelope for a voice
   */
  Modulation() noexcept : Generator("ModGen") {}

  /**
   Create new envelope for volume changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  void configure(const State& state) noexcept { configureModulationEnvelope(state); }

  /// @returns the current envelope value.
  Value value() const noexcept { return {Generator::value()}; }

  /**
   Calculate the next envelope value. This must be called on every sample for proper timing of the stages.

   @returns the new envelope value.
   */
  Value getNextValue() noexcept { return {Generator::getNextValue()}; }

  /**
   Calculate the next `count` envelope values, exactly as `count` calls to `getNextValue` would (see
   `Generator::fillBlock`).

   @param values receives the envelope values
   @param count the number of values to generate
   */
  void fillBlock(Float* values, size_t count) noexcept { Generator::fillBlock(values, nullptr, count); }

private:
  Modulation(Float sampleRate, Float delay, Float attack, Float hold, Float decay, int sustain, Float release) noexcept :
  Generator(sampleRate, "ModGen", delay, attack, hold, decay, sustain, release) {}

  friend struct EnvelopeTestInjector;
};

} // namespace SF2::Render::Envelope
