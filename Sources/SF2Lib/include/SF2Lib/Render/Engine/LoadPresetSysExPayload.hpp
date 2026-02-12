// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <cstdint>
#include <vector>

#include "SF2Util/Base64.hpp"

namespace SF2::Render::Engine {

  struct LoadPresetSysExPayload {
    static constexpr uint8_t manufacturerValue = 0x7E;
    static constexpr uint8_t modelPathPayload = 0x00; // the payload holds a path string to a file
    static constexpr uint8_t modelBookmarkPayload = 0x01; // the payload holds a bookmark to a file

    uint8_t sysExBegin;    // 0
    uint8_t manufacturer;  // 1
    uint8_t model;         // 2
    // Here lies 5 bytes of padding
    size_t presetIndex;    // 8
    size_t overrideCount;  // 16
    // SF2::MIDI::GeneratorOverride overrides[1];
    // char filePath[1];
    // uint8_t sysExEnd;   // 25 is smallest payload size

    static constexpr size_t minPayloadSize = 25;

    static std::vector<uint8_t> make(const SF2::MIDI::GeneratorOverrideVector& overrides,
                                     const std::string& filePath, size_t presetIndex) noexcept {
      auto encodedFilePath = filePath.empty() ? std::string("") : SF2::Utils::Base64::encode(filePath);
      auto payloadSize = (sizeof(LoadPresetSysExPayload)
                          + overrides.size() * sizeof(SF2::MIDI::GeneratorOverride)
                          + encodedFilePath.size()) + 1;
      auto bytes = std::vector<uint8_t>(payloadSize, 0);
      auto payload = reinterpret_cast<LoadPresetSysExPayload*>(bytes.data());
      payload->sysExBegin = SF2::valueOf(SF2::MIDI::CoreEvent::systemExclusive);
      payload->manufacturer = manufacturerValue;
      payload->model = modelPathPayload;
      payload->presetIndex = presetIndex;
      payload->overrideCount = overrides.size();
      auto pos1 = reinterpret_cast<SF2::MIDI::GeneratorOverride*>((bytes.data() + sizeof(LoadPresetSysExPayload)));
      auto pos2 = std::copy(overrides.begin(), overrides.end(), pos1);
      auto pos3 = reinterpret_cast<uint8_t*>(std::copy(encodedFilePath.begin(), encodedFilePath.end(),
                                                       reinterpret_cast<char*>(pos2)));
      *pos3++ = SF2::valueOf(SF2::MIDI::CoreEvent::EOX);

      assert(pos3 - bytes.data() == long(bytes.size()));
      assert(bytes.size() >= minPayloadSize);

      return bytes;
    }

    static std::vector<uint8_t> make(const SF2::MIDI::GeneratorOverrideVector& overrides,
                                     const NSData* bookmark, size_t presetIndex) noexcept {
      NSData* encodedBookmark = [bookmark base64EncodedDataWithOptions: 0];
      auto payloadSize = (sizeof(LoadPresetSysExPayload)
                          + overrides.size() * sizeof(SF2::MIDI::GeneratorOverride)
                          + encodedBookmark.length) + 1;
      auto bytes = std::vector<uint8_t>(payloadSize, 0);
      auto payload = reinterpret_cast<LoadPresetSysExPayload*>(bytes.data());
      payload->sysExBegin = SF2::valueOf(SF2::MIDI::CoreEvent::systemExclusive);
      payload->manufacturer = manufacturerValue;
      payload->model = modelBookmarkPayload;
      payload->presetIndex = presetIndex;
      payload->overrideCount = overrides.size();
      auto pos1 = reinterpret_cast<SF2::MIDI::GeneratorOverride*>((bytes.data() + sizeof(LoadPresetSysExPayload)));
      auto pos2 = reinterpret_cast<uint8_t*>(std::copy(overrides.begin(), overrides.end(), pos1));
      [encodedBookmark getBytes: pos2 length: encodedBookmark.length];
      auto pos3 = pos2 + encodedBookmark.length;
      *pos3++ = SF2::valueOf(SF2::MIDI::CoreEvent::EOX);

      assert(pos3 - bytes.data() == long(bytes.size()));
      assert(bytes.size() >= minPayloadSize);

      return bytes;
    }
  };

} // end namespace SF2::Render::Engine
