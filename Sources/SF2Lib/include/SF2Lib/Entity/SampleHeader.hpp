// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <string>

#include "SF2Lib/Entity/Entity.hpp"

namespace SF2::Entity {

/**
 Define the audio samples to be used for playing a specific sound.
 
 Memory layout of a 'shdr' entry. The size of this is defined to be 46 bytes, but due
 to alignment/padding the struct below is 48 bytes.
 
 The offsets (begin, end, loopBegin, and loopEnd) are indices into a big array of 16-bit integer sample values.

 From the SF2 spec:

 The values of dwStart, dwEnd, dwStartloop, and dwEndloop must all be within the range of the sample data field
 included in the SoundFont compatible bank or referenced in the sound ROM. Also, to allow a variety of hardware
 platforms to be able to reproduce the data, the samples have a minimum length of 48 data points, a minimum loop size
 of 32 data points and a minimum of 8 valid points prior to dwStartloop and after dwEndloop. Thus dwStart must be less
 than dwStartloop-7,

 dwStartloop must be less than dwEndloop-31, and dwEndloop must be less than dwEnd-7. If these constraints are not met,
 the sound may optionally not be played if the hardware cannot support artifact-free playback for the parameters given.
 */
class SampleHeader : public Entity {
public:
  static constexpr size_t entity_size = 46;
  
  enum struct Type: uint16_t {
    monoSample = 1,
    rightSample = 2,
    leftSample = 4,
    linkedSample = 8,
    rom = 0x8000
  };

  template<typename E>
  static constexpr auto toRawType(E value) noexcept { return static_cast<std::underlying_type_t<E>>(value); }

  /**
   Construct new instance from SF2 file
   */
  explicit SampleHeader(IO::Pos& pos) noexcept;

  /**
   Constructor for unit tests.
   */
  SampleHeader(uint32_t start, uint32_t end, uint32_t loopBegin, uint32_t loopEnd,
               uint32_t sampleRate, uint8_t key, int8_t adjustment = 0, uint16_t link = 0,
               Type type = Type::monoSample) noexcept;

  constexpr bool sampleIsA(Type type) const noexcept {
    return (sampleType & toRawType<Type>(type)) == toRawType<Type>(type);
  }

  /// @returns true if this sample only has one channel
  constexpr bool isMono() const noexcept { return sampleIsA(Type::monoSample); }
  
  /// @returns true if these samples generate for the right channel
  constexpr bool isRight() const noexcept { return sampleIsA(Type::rightSample); }
  
  /// @returns true if these samples generate for the left channel
  constexpr bool isLeft() const noexcept { return sampleIsA(Type::leftSample); }
  
  /// @returns true if samples come from a ROM
  constexpr bool isROM() const noexcept { return sampleIsA(Type::rom); }

  /// @returns the name assigned to the sample
  const char* sampleName() const noexcept { return achSampleName; }

  /// @returns true if there appears to be a loop in the sample. Note that this is *not* the normal way to determine if
  /// a voice will loop while rendering -- that belongs to the `sampleModes` generator.
  constexpr bool hasLoop() const noexcept {
    return dwStartLoop > dwStart && dwStartLoop < dwEndLoop && dwEndLoop <= dwEnd;
  }

  /**
   The DWORD dwStart contains the index, in sample data points, from the beginning of the sample data field to the
   first data point of this sample.

   @returns the index of the first sample to use
   */
  constexpr size_t startIndex() const noexcept { return dwStart; }
  
  /**
   The DWORD dwEnd contains the index, in sample data points, from the beginning of the sample data field to the first
   of the set of 46 zero valued data points following this sample.

   @returns index + 1 of the last sample to use.
   */
  constexpr size_t endIndex() const noexcept { return dwEnd; }

  /**
   The DWORD dwStartloop contains the index, in sample data points, from the beginning of the sample data field to the
   first data point in the loop of this sample.

   @returns index of the first sample in a loop.
   */
  constexpr size_t startLoopIndex() const noexcept { return dwStartLoop; }

  /**
   The DWORD dwEndloop contains the index, in sample data points, from the beginning of the sample data field to the
   first data point following the loop of this sample. Note that this is the data point “equivalent to” the first loop
   data point, and that to produce portable artifact free loops, the eight proximal data points surrounding both the
   Startloop and Endloop points should be identical.

   @returns index of the last + 1 of a sample in a loop.
   */
  constexpr size_t endLoopIndex() const noexcept { return dwEndLoop; }
  
  /// @returns the sample rate used to record the samples in the SF2 file
  constexpr size_t sampleRate() const noexcept { return dwSampleRate; }
  
  /// @returns the MIDI key (frequency) for the source samples.
  /// NOTE: according to spec 7.10, "Values between 128 and 254 are illegal. Whenever an illegal value or a value of
  /// 255 is encountered, the value 60 [middle C] should be used."
  constexpr int originalMIDIKey() const noexcept { return originalKey; }
  
  /// @returns the pitch correction in cents to apply when playing back the samples
  constexpr int pitchCorrection() const noexcept { return correction; }

  /// @returns number of samples between the start and end indices.
  constexpr size_t sampleSize() const noexcept { return endIndex() - startIndex(); }

  constexpr uint16_t sampleLinkIndex() const noexcept { return sampleLink; }

  void dump(const std::string& indent, size_t index) const noexcept;

private:
  std::string sampleTypeDescription() const noexcept;
  
  char achSampleName[20];
  uint32_t dwStart;
  uint32_t dwEnd;
  uint32_t dwStartLoop;
  uint32_t dwEndLoop;
  uint32_t dwSampleRate;
  // *** PADDING ***
  uint8_t originalKey;
  int8_t correction;
  uint16_t sampleLink;
  uint16_t sampleType;
};

} // end namespace SF2::Entity
