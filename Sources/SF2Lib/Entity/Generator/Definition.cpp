// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <iostream>

#include "SF2Lib/Entity/Generator/Generator.hpp"

using namespace SF2::Entity::Generator;

void
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
  }
  
  std::cout << " (" << (isUnsignedValue() ? amount.unsignedAmount() : amount.signedAmount()) << ')';
}

// Allow compile-time check that A is a real Index value and then convert to string.
#define N(A) (Index::A != Index::numValues) ? (# A) : nullptr

std::array<Definition, Definition::NumDefs> const Definition::definitions_{
  Definition(N(startAddressOffset), ValueKind::offset, 															{               }, false, 1),
  Definition(N(endAddressOffset), ValueKind::offset, 																{               }, false, 1),
  Definition(N(startLoopAddressOffset), ValueKind::offset, 													{               }, false, 1),
  Definition(N(endLoopAddressOffset), ValueKind::offset, 														{               }, false, 1),
  Definition(N(startAddressCoarseOffset), ValueKind::coarseOffset, 									{               }, false, 1),
  // 5
  Definition(N(modulatorLFOToPitch), ValueKind::signedCents,												{-12'000, 12'000}, true, 2),
  Definition(N(vibratoLFOToPitch), ValueKind::signedCents, 													{-12'000, 12'000}, true, 2),
  Definition(N(modulatorEnvelopeToPitch), ValueKind::signedCents, 									{-12'000, 12'000}, true, 2),
  Definition(N(initialFilterCutoff), ValueKind::signedFrequencyCents, 							{  1'500, 13'500}, true, 2),
  Definition(N(initialFilterResonance), ValueKind::signedCentsBel, 									{      0,    960}, true, 1),
  // 10
  Definition(N(modulatorLFOToFilterCutoff), ValueKind::signedShort, 								{-12'000, 12'000}, true, 2),
  Definition(N(modulatorEnvelopeToFilterCutoff), ValueKind::signedShort, 						{-12'000, 12'000}, true, 2),
  Definition(N(endAddressCoarseOffset), ValueKind::coarseOffset, 										{               }, false, 1),
  Definition(N(modulatorLFOToVolume), ValueKind::signedCentsBel, 										{   -960,    960}, true, 1),
  Definition(N(unused1), ValueKind::signedShort, 																		{               }, false, 0),
  // 15
  Definition(N(chorusEffectSend), ValueKind::unsignedPercent, 											{      0,  1'000}, true, 1),
  Definition(N(reverbEffectSend), ValueKind::unsignedPercent, 											{      0,  1'000}, true, 1),
  Definition(N(pan), ValueKind::signedPercent, 																			{   -500,    500}, true, 1),
  Definition(N(unused2), ValueKind::unsignedShort, 																	{               }, false, 0),
  Definition(N(unused3), ValueKind::unsignedShort, 																	{               }, false, 0),
  // 20
  Definition(N(unused4), ValueKind::unsignedShort, 																	{               }, false, 0),
  Definition(N(delayModulatorLFO), ValueKind::signedTimeCents, 											{-12'000,  5'000}, true, 2),
  Definition(N(frequencyModulatorLFO), ValueKind::signedFrequencyCents, 						{-16'000,  4'500}, true, 4),
  Definition(N(delayVibratoLFO), ValueKind::signedTimeCents, 												{-12'000,  5'000}, true, 2),
  Definition(N(frequencyVibratoLFO), ValueKind::signedFrequencyCents, 							{-16'000,  4'500}, true, 4),
  // 25
  Definition(N(delayModulatorEnvelope), ValueKind::signedTimeCents, 								{-12'000,  5'000}, true, 2),
  Definition(N(attackModulatorEnvelope), ValueKind::signedTimeCents, 								{-12'000,  8'000}, true, 2),
  Definition(N(holdModulatorEnvelope), ValueKind::signedTimeCents, 									{-12'000,  5'000}, true, 2),
  Definition(N(decayModulatorEnvelope), ValueKind::signedTimeCents, 								{-12'000,  8'000}, true, 2),
  Definition(N(sustainModulatorEnvelope), ValueKind::unsignedPercent, 							{      0,  1'000}, true, 1),
  // 30
  Definition(N(releaseModulatorEnvelope), ValueKind::signedTimeCents, 							{-12'000,  8'000}, true, 2),
  Definition(N(midiKeyToModulatorEnvelopeHold), ValueKind::signedShort, 						{ -1'200,  1'200}, true, 1),
  Definition(N(midiKeyToModulatorEnvelopeDecay), ValueKind::signedShort, 						{ -1'200,  1'200}, true, 1),
  Definition(N(delayVolumeEnvelope), ValueKind::signedTimeCents, 										{-12'000,  5'000}, true, 2),
  Definition(N(attackVolumeEnvelope), ValueKind::signedTimeCents, 									{-12'000,  8'000}, true, 2),
  // 35
  Definition(N(holdVolumeEnvelope), ValueKind::signedTimeCents, 										{-12'000,  5'000}, true, 2),
  Definition(N(decayVolumeEnvelope), ValueKind::signedTimeCents, 										{-12'000,  8'000}, true, 2),
  Definition(N(sustainVolumeEnvelope), ValueKind::signedCentsBel, 									{      0,  1'440}, true, 1),
  Definition(N(releaseVolumeEnvelope), ValueKind::signedTimeCents, 									{-12'000,  8'000}, true, 2),
  Definition(N(midiKeyToVolumeEnvelopeHold), ValueKind::signedShort, 								{ -1'200,  1'200}, true, 1),
  // 40
  Definition(N(midiKeyToVolumeEnvelopeDecay), ValueKind::signedShort, 							{ -1'200,  1'200}, true, 1),
  Definition(N(instrument), ValueKind::unsignedShort, 															{               }, true, 0),
  Definition(N(reserved1), ValueKind::signedShort, 																	{               }, false, 0),
  Definition(N(keyRange), ValueKind::range, 																				{               }, true, 0),
  Definition(N(velocityRange), ValueKind::range, 																		{               }, true, 0),
  // 45
  Definition(N(startLoopAddressCoarseOffset), ValueKind::coarseOffset, 							{               }, false, 1),
  Definition(N(forcedMIDIKey), ValueKind::signedShort, 															{     -1,    127}, false, 0),
  Definition(N(forcedMIDIVelocity), ValueKind::signedShort, 												{     -1,    127}, false, 1),
  Definition(N(initialAttenuation), ValueKind::signedCentsBel, 											{      0,  1'440}, true, 1),
  Definition(N(reserved2), ValueKind::unsignedShort, 																{               }, false, 0),
  // 50
  Definition(N(endLoopAddressCoarseOffset), ValueKind::coarseOffset, 								{               }, false, 1),
  Definition(N(coarseTune), ValueKind::signedSemitones, 														{   -120,    120}, true, 1),
  Definition(N(fineTune), ValueKind::signedCents, 																	{    -99,     99}, true, 1),
  Definition(N(sampleID), ValueKind::unsignedShort, 																{               }, false, 0),
  Definition(N(sampleModes), ValueKind::unsignedShort, 															{               }, false, 0),
  // 55
  Definition(N(reserved3), ValueKind::signedShort, 																	{               }, false, 0),
  Definition(N(scaleTuning), ValueKind::unsignedShort, 															{      0,   1200}, true, 1),
  Definition(N(exclusiveClass), ValueKind::unsignedShort, 													{      0,    127}, false, 0),
  Definition(N(overridingRootKey), ValueKind::signedShort, 													{     -1,    127}, false, 0),
};
