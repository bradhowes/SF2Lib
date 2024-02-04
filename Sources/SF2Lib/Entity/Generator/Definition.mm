// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <iostream>

#include "SF2Lib/DSP.hpp"
#include "SF2Lib/Entity/Generator/Definition.hpp"

using namespace SF2;
using namespace SF2::Entity::Generator;

Definition::Definition(const char* name, ValueKind valueKind, ValueRange minMax, bool availableInPreset,
                       NRPNMultiplier nrpnMultiplier) noexcept :
name_{name},
valueRange_{minMax},
valueKind_{valueKind},
nrpnMultiplier_{nrpnMultiplier},
availableInPreset_{availableInPreset}
{
  ;
}

Float
Definition::convertedValueOf(const Amount& amount) const noexcept
{
  switch (valueKind_) {
    case ValueKind::coarseOffset: return valueOf(amount) * 32768;
    case ValueKind::signedCents: return valueOf(amount) / 1200_F;
    case ValueKind::signedCentsBel:
    case ValueKind::unsignedPercent:
    case ValueKind::signedPercent: return valueOf(amount) / 10_F;
    case ValueKind::signedFrequencyCents: return DSP::centsToFrequency(valueOf(amount));
    case ValueKind::signedTimeCents: return DSP::centsToSeconds(valueOf(amount));
    default: return valueOf(amount);
  }
}

std::ostream&
Definition::dump(const Amount& amount) const noexcept
{
  Float value = convertedValueOf(amount);
  switch (valueKind_) {
    case ValueKind::unsignedShort: std::cout << value; break;
    case ValueKind::offset: std::cout << value << " bytes"; break;
    case ValueKind::coarseOffset: std::cout << value << " bytes"; break;
    case ValueKind::signedShort: std::cout << value; break;
    case ValueKind::signedCents: std::cout << value << " oct"; break;
    case ValueKind::signedCentsBel: std::cout << value << " dB"; break;
    case ValueKind::unsignedPercent: std::cout << value << "%"; break;
    case ValueKind::signedPercent: std::cout << value << "%"; break;
    case ValueKind::signedFrequencyCents: std::cout << value << " Hz"; break;
    case ValueKind::signedTimeCents: std::cout << value << " seconds"; break;
    case ValueKind::signedSemitones: std::cout << value << " notes"; break;
    case ValueKind::range: std::cout << '[' << amount.low() << '-' << amount.high() << ']'; break;
    default: break;
  }

  return std::cout << " (" << (isUnsignedValue() ? amount.unsignedAmount() : amount.signedAmount()) << ')';
}

// Allow compile-time check that A is a real Index value and then convert to string.
#define N(A) (Index::A != Index::numValues) ? (# A) : nullptr

using D = class Definition;

GeneratorValueArray<Definition> const Definition::definitions_{
  //  Name               Kind                                  Value Range        Preset? NRPN Multiplier
  //  ------------------ ------------------------------------- ------------------ ------- -------------------
  D{N(startAddressOffset),                   ValueKind::offset,	    shortIntRange, false, NRPNMultiplier::x1},
  D{N(endAddressOffset),                     ValueKind::offset,	    shortIntRange, false, NRPNMultiplier::x1},
  D{N(startLoopAddressOffset),               ValueKind::offset,     shortIntRange, false, NRPNMultiplier::x1},
  D{N(endLoopAddressOffset),                 ValueKind::offset, 	  shortIntRange, false, NRPNMultiplier::x1},
  D{N(startAddressCoarseOffset),       ValueKind::coarseOffset,     shortIntRange, false, NRPNMultiplier::x1},
  // 5
  D{N(modulatorLFOToPitch),             ValueKind::signedCents,	{-12'000, 12'000}, true,  NRPNMultiplier::x2},
  D{N(vibratoLFOToPitch),               ValueKind::signedCents,	{-12'000, 12'000}, true,  NRPNMultiplier::x2},
  D{N(modulatorEnvelopeToPitch),        ValueKind::signedCents,	{-12'000, 12'000}, true,  NRPNMultiplier::x2},
  D{N(initialFilterCutoff),    ValueKind::signedFrequencyCents, {  1'500, 13'500}, true,  NRPNMultiplier::x2},
  D{N(initialFilterResonance),       ValueKind::signedCentsBel,	{      0,    960}, true,  NRPNMultiplier::x1},
  // 10
  D{N(modulatorLFOToFilterCutoff),      ValueKind::signedShort, {-12'000, 12'000}, true,  NRPNMultiplier::x2},
  D{N(modulatorEnvelopeToFilterCutoff), ValueKind::signedShort, {-12'000, 12'000}, true,  NRPNMultiplier::x2},
  D{N(endAddressCoarseOffset),         ValueKind::coarseOffset,	    shortIntRange, false, NRPNMultiplier::x1},
  D{N(modulatorLFOToVolume),         ValueKind::signedCentsBel, {   -960,    960}, true,  NRPNMultiplier::x1},
  D{N(unused1),                              ValueKind::UNUSED,	      unusedRange, false, NRPNMultiplier::x1},
  // 15
  D{N(chorusEffectSend),            ValueKind::unsignedPercent, {      0,  1'000}, true,  NRPNMultiplier::x1},
  D{N(reverbEffectSend),            ValueKind::unsignedPercent, {      0,  1'000}, true,  NRPNMultiplier::x1},
  D{N(pan),                           ValueKind::signedPercent,	{   -500,    500}, true,  NRPNMultiplier::x1},
  D{N(unused2),                              ValueKind::UNUSED,	      unusedRange, false, NRPNMultiplier::x1},
  D{N(unused3),                              ValueKind::UNUSED,	      unusedRange, false, NRPNMultiplier::x1},
  // 20
  D{N(unused4),                              ValueKind::UNUSED, 	    unusedRange, false, NRPNMultiplier::x1},
  D{N(delayModulatorLFO),           ValueKind::signedTimeCents,	{-12'000,  5'000}, true,  NRPNMultiplier::x2},
  D{N(frequencyModulatorLFO),  ValueKind::signedFrequencyCents,	{-16'000,  4'500}, true,  NRPNMultiplier::x4},
  D{N(delayVibratoLFO),             ValueKind::signedTimeCents,	{-12'000,  5'000}, true,  NRPNMultiplier::x2},
  D{N(frequencyVibratoLFO),    ValueKind::signedFrequencyCents, {-16'000,  4'500}, true,  NRPNMultiplier::x4},
  // 25
  D{N(delayModulatorEnvelope),      ValueKind::signedTimeCents, {-12'000,  5'000}, true,  NRPNMultiplier::x2},
  D{N(attackModulatorEnvelope),     ValueKind::signedTimeCents, {-12'000,  8'000}, true,  NRPNMultiplier::x2},
  D{N(holdModulatorEnvelope),       ValueKind::signedTimeCents,	{-12'000,  5'000}, true,  NRPNMultiplier::x2},
  D{N(decayModulatorEnvelope),      ValueKind::signedTimeCents,	{-12'000,  8'000}, true,  NRPNMultiplier::x2},
  D{N(sustainModulatorEnvelope),    ValueKind::unsignedPercent,	{      0,  1'000}, true,  NRPNMultiplier::x1},
  // 30
  D{N(releaseModulatorEnvelope),    ValueKind::signedTimeCents, {-12'000,  8'000}, true,  NRPNMultiplier::x2},
  D{N(midiKeyToModulatorEnvelopeHold),  ValueKind::signedShort,	{ -1'200,  1'200}, true,  NRPNMultiplier::x1},
  D{N(midiKeyToModulatorEnvelopeDecay), ValueKind::signedShort, { -1'200,  1'200}, true,  NRPNMultiplier::x1},
  D{N(delayVolumeEnvelope),         ValueKind::signedTimeCents,	{-12'000,  5'000}, true,  NRPNMultiplier::x2},
  D{N(attackVolumeEnvelope),        ValueKind::signedTimeCents,	{-12'000,  8'000}, true,  NRPNMultiplier::x2},
  // 35
  D{N(holdVolumeEnvelope),          ValueKind::signedTimeCents, {-12'000,  5'000}, true,  NRPNMultiplier::x2},
  D{N(decayVolumeEnvelope),         ValueKind::signedTimeCents, {-12'000,  8'000}, true,  NRPNMultiplier::x2},
  D{N(sustainVolumeEnvelope),        ValueKind::signedCentsBel, {      0,  1'440}, true,  NRPNMultiplier::x1},
  D{N(releaseVolumeEnvelope),       ValueKind::signedTimeCents, {-12'000,  8'000}, true,  NRPNMultiplier::x2},
  D{N(midiKeyToVolumeEnvelopeHold),     ValueKind::signedShort, { -1'200,  1'200}, true,  NRPNMultiplier::x1},
  // 40
  D{N(midiKeyToVolumeEnvelopeDecay),    ValueKind::signedShort,	{ -1'200,  1'200}, true,  NRPNMultiplier::x1},
  D{N(instrument),                    ValueKind::unsignedShort,    ushortIntRange, true,  NRPNMultiplier::x1},
  D{N(reserved1),                            ValueKind::UNUSED,       unusedRange, false, NRPNMultiplier::x1},
  D{N(keyRange),                              ValueKind::range, 	       keyRange, true,  NRPNMultiplier::x1},
  D{N(velocityRange),                         ValueKind::range, 	       keyRange, true,  NRPNMultiplier::x1},
  // 45
  D{N(startLoopAddressCoarseOffset),   ValueKind::coarseOffset,	    shortIntRange, false, NRPNMultiplier::x1},
  D{N(forcedMIDIKey),                   ValueKind::signedShort,      neg1KeyRange, false, NRPNMultiplier::x1},
  D{N(forcedMIDIVelocity),              ValueKind::signedShort,      neg1KeyRange, false, NRPNMultiplier::x1},
  D{N(initialAttenuation),           ValueKind::signedCentsBel,	{      0,  1'440}, true,  NRPNMultiplier::x1},
  D{N(reserved2),                            ValueKind::UNUSED,	      unusedRange, false, NRPNMultiplier::x1},
  // 50
  D{N(endLoopAddressCoarseOffset),     ValueKind::coarseOffset,	    shortIntRange, false, NRPNMultiplier::x1},
  D{N(coarseTune),                  ValueKind::signedSemitones,	{   -120,    120}, true,  NRPNMultiplier::x1},
  D{N(fineTune),                        ValueKind::signedCents,	{    -99,     99}, true,  NRPNMultiplier::x1},
  D{N(sampleID),                      ValueKind::unsignedShort,	   ushortIntRange, false, NRPNMultiplier::x1},
  D{N(sampleModes),                   ValueKind::unsignedShort,	   ushortIntRange, false, NRPNMultiplier::x1},
  // 55
  D{N(reserved3),                            ValueKind::UNUSED,	      unusedRange, false, NRPNMultiplier::x1},
  D{N(scaleTuning),                   ValueKind::unsignedShort,	{      0,   1200}, true,  NRPNMultiplier::x1},
  D{N(exclusiveClass),                ValueKind::unsignedShort,          keyRange, false, NRPNMultiplier::x1},
  D{N(overridingRootKey),               ValueKind::signedShort, 		 neg1KeyRange, false, NRPNMultiplier::x1},
};
