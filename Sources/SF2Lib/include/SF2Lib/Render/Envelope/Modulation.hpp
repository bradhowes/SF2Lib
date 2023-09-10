// Copyright © 2022 Brad Howes. All rights reserved.

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

  struct Value {
    inline Value(Float v) noexcept : val{v} {}
    const Float val;
  };

  explicit Modulation(size_t voiceIndex) : Generator(voiceIndex, "ModGen") {}

  /**
   Create new envelope for volume changes over time.

   @param state the state holding the generator values for the envelope definition
   */
  void configure(const State& state) noexcept { configureModulationEnvelope(state); }

  /// @returns the current envelope value.
  inline Value value() const noexcept { return Generator::value(); }

  /**
   Calculate the next envelope value. This must be called on every sample for proper timing of the stages.

   @returns the new envelope value.
   */
  Value getNextValue() noexcept { return Generator::getNextValue(); }

private:
  Modulation(Float sampleRate, size_t voiceIndex, Float delay, Float attack, Float hold, Float decay,
             int sustain, Float release) noexcept;

  friend struct EnvelopeTestInjector;
};

} // namespace SF2::Render::Envelope
