// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <iostream>

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/LFO.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

namespace SF2::Render::Voice::Sample {

/**
 View of a State that pertains to pitch. Pitch is based on the MIDI key that triggered the note, several
 generator values that are set by instrument and preset zones, and values found in the sample header that
 spells out how the samples were originally recorded.

 - State::key() -- the MIDI key *or* the value from the `forcedMIDIKey` generator.
 - SampleHeader::originalMIDIKey -- the note of the original samples
 - SampleHeader::pitchCorrection -- adjustment to apply to have the samples really play at originalMIDIKey
 frequency
 - SampleHeader::sampleRate -- the sample rate used when recording the samples
 - State::sampleRate -- the sample rate in effect when rendering new samples
 - `overridingRootKey` -- generator that overrides `originalMIDIKey` in sample header
 - `scaleTuning` -- generator that sets the number of cents that increase as key numbers increase
 - `coarseTune` -- modulated generator that changes pitch in semitones
 - `fineTune` -- modulated generator that changes pitch in cents

 All but the last two items are fixed when Pitch instance is created. If/when those two items change due to
 modulation, one must call `Pitch::updatePitchOffset` to have them affect future frequency calculations.

 The routine `Pitch::samplePhaseIncrement` generates the appropriate increment to use when rendering audio
 samples from the original ones. If the target frequency is the same as the root one, then the increment would
 be 1.0. If the event key is an octave higher than the original root key, the increment would be 2.0 since we
 need to move past 2x the same number of samples to get 2x cycles in the same amount of time.

 This routine takes into account current modulation and vibrato LFO values as well as the current modulation
 envelope. These all can affect the pitch that is used in the increment calculations depending on the state
 generators `modulatorLFOToPitch`, `vibratoLFOToPitch` and `modulatorEnvelopeToPitch`.
 */
class Pitch
{
public:
  using Index = State::State::Index;
  using Modulation = Envelope::Modulation;

  /**
   Construct new instance. NOTE: the instance is not usable for audio rendering at this point. One must call
   `configure` in order to be useable for rendering purposes.

   @param state the state to use for pitch calculations
   */
  Pitch(const State::State& state) noexcept : state_{state}
  {}

  /**
   Configure instance to use the given sample definition. NOTE: this is invoked before start of rendering a note. This
   routine *must* ensure that the state is properly setup to do so, just as if it was created from scratch.

   @param header the sample header to use
   */
  void configure(const Entity::SampleHeader& header) noexcept
  {
    /*
     Spec 7.10:
     
     The BYTE byOriginalPitch contains the MIDI key number of the recorded pitch of the sample. For example, a
     recording of an instrument playing middle C (261.62 Hz) should receive a value of 60. This value is used as the
     default “root key” for the sample, so that in the example, a MIDI key-on command for note number 60 would
     reproduce the sound at its original pitch. For unpitched sounds, a conventional value of 255 should be used.
     Values between 128 and 254 are illegal. Whenever an illegal value or a value of 255 is encountered, the value 60
     should be used.
     */
    auto rootKey = header.originalMIDIKey();
    auto constantPitch = rootKey == 255;
    if (rootKey > 127) {
      rootKey = 60;
    }

    /*
     Spec 8.1.2 - overridingRootKey:

     This parameter represents the MIDI key number at which the sample is to be played back at its original sample
     rate. If not present, or if present with a value of -1, then the sample header parameter Original Key is used in
     its place. If it is present in the range 0-127, then the indicated key number will cause the sample to be played
     back at its sample header Sample Rate. For example, if the sample were a recording of a piano middle C
     (Original Key = 60) at a sample rate of 22.050 kHz, and Root Key were set to 69, then playing MIDI key number 69
     (A above middle C) would cause a piano note of pitch middle C to be heard.
     */
    auto value = state_.unmodulated(Index::overridingRootKey);
    if (value >= 0 && value < 128) {
      rootKey = value;
      constantPitch = false; // Unclear in spec if this should be the case.
    }

    auto sampleRateDeltaCents = 0;
    if (state_.sampleRate() != header.sampleRate()) {
      // Calculate ratio of sample rates as a difference in their cent frequency values, which can then be added to
      // the sum of the phase increments. Saves us from a multiply later on.
      auto sampleRateCents = int(std::round(1200 * std::log2(state_.sampleRate() / 440.0)));
      auto originalSampleRateCents = int(std::round(1200 * std::log2(header.sampleRate() / 440.0)));
      sampleRateDeltaCents = originalSampleRateCents - sampleRateCents;
    }

    /*
     Spec 8.1.2 - scaleTuning:

     This parameter represents the degree to which MIDI key number influences pitch. A value of zero indicates that
     MIDI key number has no effect on pitch; a value of 100 represents the usual tempered semitone scale.
     */
    auto keyCents = constantPitch ? 0.0f : state_.unmodulated(Index::scaleTuning) * (state_.key() - rootKey);
    phaseBase_ = keyCents + header.pitchCorrection() + sampleRateDeltaCents;
  }

  /**
   Calculate the sample increment to use when rendering. If the target frequency is the same as the root frequency, then
   this would be 1. For a target frequency that is twice the root frequency, then this would be 2.0 since we need to
   move past 2x the same number of samples to get twice the cycle frequency.

   @param modLFO the current modulation LFO value
   @param vibLFO the current vibrato LFO value
   @param modEnv the current modulation envelope value
   */
  Float samplePhaseIncrement(ModLFO::Value modLFO, VibLFO::Value vibLFO, Modulation::Value modEnv) const noexcept
  {
    auto coarseTune = state_.modulated(Index::coarseTune);
    auto fineTune = state_.modulated(Index::fineTune);
    auto phaseOffset = coarseTune * 100.0 + fineTune;

    auto modLFOValue = modLFO.val * state_.modulated(Index::modulatorLFOToPitch);
    auto vibLFOValue = vibLFO.val * state_.modulated(Index::vibratoLFOToPitch);
    auto modEnvValue = modEnv.val * state_.modulated(Index::modulatorEnvelopeToPitch);

    auto phase = phaseBase_ + phaseOffset + modLFOValue + vibLFOValue + modEnvValue;
    auto phaseIncrement = DSP::power2Lookup(int(std::round(phase)));

    return phaseIncrement;
  }

private:

  const State::State& state_;
  Float phaseBase_;
};

} // namespace SF2::Render
