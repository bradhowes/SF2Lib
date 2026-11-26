// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <cstdint>
#include <vector>

#include "DSPHeaders/Types.hpp"
#include "SF2Util/Base64.hpp"

namespace SF2::Render::Engine {

  struct LoadPresetSysExPayload {
    static constexpr uint8_t manufacturerValue = 0x7C; // public non-commercial (for now)
    static constexpr uint8_t modelPathPayload = 0x00; // the payload holds a path string to a file
    static constexpr uint8_t modelBookmarkPayload = 0x01; // the payload holds a bookmark to a file

    uint8_t sysExBegin;    // 0
    uint8_t manufacturer;  // 1
    uint8_t model;         // 2
    // char base_64_payload[1]; N
    uint8_t sysExEnd;      // N + 1

    struct Fixed {
      size_t presetIndex;
      size_t overrideCount;
      // MIDI::GeneratorOverride override[1]; // variable size based on overrideCount value
      // char path[1]; // bookmark or string
    };

    static constexpr size_t minPayloadSize = 25;

    /**
     Create a new SysEx payload to switch to another sound font and preset + zero or more override settings for generators (TODO).
     NOTE: this is for entities wishing to command SF2Lib to use a new preset and font file. It is *not* used by SF2Lib itself
     so we are free to do memory allocations here.

     @param overrides collection of `GeneratorOveride` entities to apply to the preset.
     @param filePath the location of the font file to use. If empty, and only change the preset of the currently loaded font file.
     @param presetIndex the index of the preset to load

     @returns MIDI SysEx payload that can be sent to an SF2Lib synth
     */
    static std::vector<uint8_t>
    make(const MIDI::GeneratorOverrideVector& overrides, const std::string& filePath, size_t presetIndex) {

      // The payload for the SysEx message.
      auto payloadSize = (sizeof(Fixed)
                          + overrides.size() * sizeof(MIDI::GeneratorOverride)
                          + filePath.size());
      auto payloadBytes = std::vector<uint8_t>(payloadSize, 0);
      auto payloadPtr = reinterpret_cast<Fixed*>(payloadBytes.data());

      payloadPtr->presetIndex = presetIndex;
      payloadPtr->overrideCount = overrides.size();

      // Add any overrides
      auto overridePtr = reinterpret_cast<MIDI::GeneratorOverride*>(payloadPtr + 1);
      auto pathPtr = reinterpret_cast<char*>(std::copy(overrides.begin(), overrides.end(), overridePtr));

      // Copy over the file path.
      auto endPos = reinterpret_cast<uint8_t*>(std::copy(filePath.begin(), filePath.end(), pathPtr));

      // Generate Base64 encoding.
      auto encodedPayload = SF2::Utils::Base64::encode({payloadBytes.data(), endPos});

      // Create the SysEx message without any bytes > 0x7F.
      auto msg = std::vector<uint8_t>(encodedPayload.size() + 4);
      msg[0] = DSPHeaders::valueOf(SF2::MIDI::CoreEvent::systemExclusive);
      msg[1] = manufacturerValue;
      msg[2] = modelPathPayload;
      std::copy(encodedPayload.begin(), encodedPayload.end(), reinterpret_cast<char*>(msg.data() + 3));
      msg[msg.size() - 1] = DSPHeaders::valueOf(SF2::MIDI::CoreEvent::EOX);

      return msg;
    }

    /**
     Create a new SysEx payload to switch to another sound font and preset + zero or more override settings for generators (TODO).
     NOTE: this is for entities wishing to command SF2Lib to use a new preset and font file. It is *not* used by SF2Lib itself
     so we are free to do memory allocations here.

     @param overrides collection of `GeneratorOveride` entities to apply to the preset.
     @param bookmark the location of the font file to use. If nullptr or empty, only change the preset of the currently loaded
     font file.
     @param presetIndex the index of the preset to load

     @returns MIDI SysEx payload that can be sent to an SF2Lib synth
     */
    static std::vector<uint8_t>
    make(const SF2::MIDI::GeneratorOverrideVector& overrides, const NSData* bookmark, size_t presetIndex) {

      size_t bookmarkSize = bookmark != nullptr ? bookmark.length : 0;

      // The payload for the SysEx message.
      auto payloadSize = (sizeof(Fixed)
                          + overrides.size() * sizeof(MIDI::GeneratorOverride)
                          + bookmarkSize);
      auto payloadBytes = std::vector<uint8_t>(payloadSize, 0);
      auto payloadPtr = reinterpret_cast<Fixed*>(payloadBytes.data());

      payloadPtr->presetIndex = presetIndex;
      payloadPtr->overrideCount = overrides.size();

      // Add any overrides
      auto overridePtr = reinterpret_cast<MIDI::GeneratorOverride*>(payloadPtr + 1);
      auto pathPtr = reinterpret_cast<char*>(std::copy(overrides.begin(), overrides.end(), overridePtr));

      // Copy over the bookmark data.
      if (bookmark != nullptr) {
        [bookmark getBytes: pathPtr length: bookmark.length];
      }

      // Generate Base64 encoding.
      auto endPos = reinterpret_cast<uint8_t*>(pathPtr + bookmarkSize);
      auto encodedPayload = SF2::Utils::Base64::encode({payloadBytes.data(), endPos});

      // Create the SysEx message without any bytes > 0x7F.
      auto msg = std::vector<uint8_t>(encodedPayload.size() + 4);
      msg[0] = DSPHeaders::valueOf(SF2::MIDI::CoreEvent::systemExclusive);
      msg[1] = manufacturerValue;
      msg[2] = modelBookmarkPayload;
      std::copy(encodedPayload.begin(), encodedPayload.end(), reinterpret_cast<char*>(msg.data() + 3));
      msg[msg.size() - 1] = DSPHeaders::valueOf(SF2::MIDI::CoreEvent::EOX);

      return msg;
    }
  };

} // end namespace SF2::Render::Engine
