// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>
#include <vector>

#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/WithCollectionBase.hpp"
#include "SF2Lib/Render/Zone/Preset.hpp"

namespace SF2::IO {
class File;
}

namespace SF2::Render {

/**
 Representation of a `preset` in an SF2 file used for rendering. A preset is made up of one or more zones, where a zone is defined
 as a collection of generators and modulators that apply for a particular MIDI key number and/or velocity.

 All preset zone generators except for the very first must end with generator index #41 `instrument` which indicates
 which `Instrument` to use for the basis for audio rendering. If the first zone of a preset does not end with an
 `instrument` generator, then it is considered to be the one and only `global` preset zone, with its generators and
 modulators applied to all other zones unless a zone has its own definition.

 Note that preset zones can overlap, so one MIDI key event can cause multiple instruments to play, each of which will
 require its own Voice instance to render.
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
  Preset(IO::File& file, InstrumentCollection& instruments, const Entity::Preset& config) noexcept;

  /**
   Create a `SamplesVector` that contains the normalized samples for the preset, and installs spans over it for each instrument in
   the preset.

   @param file the SF2 file that holds the samples
   @returns `true` if successful, `false` otherwise
   */
  bool loadSamples(const IO::File& file) noexcept;

  /**
   Remove normalized samples. NOTE: once called, any attempt to use the preset will fail until `loadSamples` is invoked.
   */
  void clearSamples() noexcept;

  /**
   Locate preset/instrument zones for the given key/velocity values. There can be more than one match, often due to
   separate left/right channels for rendering, or layered sounds. Each match will require its own `Voice` for rendering.

   @param key the MIDI key to filter with
   @param velocity the MIDI velocity to filter with
   @returns vector of Voice::State::Config instances containing the zones to use
   */
  ConfigCollection find(int key, int velocity) const noexcept;

private:
  SampleVector normalizedSamples_{};
  inline static const os_log_t log_{Log::create("Preset")};
};

} // namespace SF2::Render
