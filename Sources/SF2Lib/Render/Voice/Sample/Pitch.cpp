// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/Sample/Pitch.hpp"

using namespace SF2::Render::Voice::Sample;

void
Pitch::configure(const Entity::SampleHeader& header) noexcept
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
  auto rootKey{header.originalMIDIKey()};
  auto constantPitch{rootKey == 255};
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
  auto value{state_.unmodulated(Index::overridingRootKey)};
  if (value >= 0 && value < 128) {
    rootKey = value;
    constantPitch = false; // Unclear in spec if this should be the case.
  }

  auto sampleRateDeltaCents{0};
  if (state_.sampleRate() != header.sampleRate()) {
    // Calculate ratio of sample rates as a difference in their cent frequency values, which can then be added to
    // the sum of the phase increments. Saves us from a multiply later on.
    auto sampleRateCents{int(std::round(1200 * std::log2(state_.sampleRate() / 440.0)))};
    auto originalSampleRateCents{int(std::round(1200 * std::log2(header.sampleRate() / 440.0)))};
    sampleRateDeltaCents = originalSampleRateCents - sampleRateCents;
  }

  /*
   Spec 8.1.2 - scaleTuning:

   This parameter represents the degree to which MIDI key number influences pitch. A value of zero indicates that
   MIDI key number has no effect on pitch; a value of 100 represents the usual tempered semitone scale.
   */
  auto keyCents{constantPitch ? 0.0f : state_.unmodulated(Index::scaleTuning) * (state_.key() - rootKey)};
  phaseBase_ = keyCents + header.pitchCorrection() + sampleRateDeltaCents;
}
