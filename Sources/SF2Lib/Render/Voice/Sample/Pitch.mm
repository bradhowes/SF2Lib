// Copyright © 2022 Brad Howes. All rights reserved.

#include <algorithm>
#include <cmath>

#include "SF2File/Entity/SampleHeader.hpp"
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

  // SF2.01 7.10: "A value of zero is illegal. If an illegal or impractical value is encountered, the nearest practical
  // value should be used." The spec gives 400 Hz as the lowest practical rate.
  auto headerSampleRate{std::max<Float>(header.sampleRate(), 400_F)};

  auto sampleRateDeltaCents{0_F};
  if (state_.sampleRate() != headerSampleRate) {
    // Express the exact sample-rate ratio in cents so it can be folded into the phase increment below. Computing the
    // ratio directly avoids the error from converting both rates to cents and rounding them independently.
    sampleRateDeltaCents = 1200_F * std::log2(headerSampleRate / state_.sampleRate());
  }

  /*
   Spec 8.1.2 - scaleTuning:

   This parameter represents the degree to which MIDI key number influences pitch. A value of zero indicates that
   MIDI key number has no effect on pitch; a value of 100 represents the usual tempered semitone scale.
   */
  auto keyCents{constantPitch ? 0_F : state_.unmodulated(Index::scaleTuning) * (state_.key() - rootKey)};
  phaseBase_ = keyCents + header.pitchCorrection() + sampleRateDeltaCents;
}
