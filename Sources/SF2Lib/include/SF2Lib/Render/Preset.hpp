// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/WithCollectionBase.hpp"
#include "SF2Lib/Render/Zone/Preset.hpp"

namespace SF2::IO {
class File;
}

namespace SF2::Render {

/**
 Represents a preset that knows how to emit sounds for MIDI events when it is active.

 A preset is made up of a collection of zones, where each zone defines a MIDI key and velocity range that it applies to
 and an instrument that determines the sound to produce. Note that zones can overlap, so one MIDI key event can cause
 multiple instruments to play, each of which will require its own Voice instance to render.
 */
class Preset : public WithCollectionBase<Zone::Preset, Entity::Preset> {
public:
  using ConfigCollection = std::vector<Voice::State::Config>;

  /**
   Construct new Preset from SF2 entities

   @param file the SF2 file that is loaded
   @param instruments the collection of instruments that apply to the preset
   @param config the SF2 preset definition
   */
  Preset(const IO::File& file, const InstrumentCollection& instruments, const Entity::Preset& config) noexcept;

  /**
   Locate preset/instrument zones for the given key/velocity values. There can be more than one match, often due to
   separate left/right channels for rendering. Each match will require its own Voice for rendering.

   @param key the MIDI key to filter with
   @param velocity the MIDI velocity to filter with
   @returns vector of Voice:Config instances containing the zones to use
   */
  ConfigCollection find(int key, int velocity) const noexcept;
};

} // namespace SF2::Render
