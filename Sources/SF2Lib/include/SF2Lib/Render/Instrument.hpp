// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Render/Zone/Instrument.hpp"
#include "SF2Lib/Render/WithCollectionBase.hpp"

namespace SF2::IO { class File; }
namespace SF2::Render {

/**
 Representation of an `instrument` in an SF2 file. An instrument is made up of one or more zones, where a zone is
 defined as a collection of generators and modulators that apply for a particular MIDI key value and/or velocity.
 All instrument zone generators except the very first must end with generator index #53 `sampleID` which indicates
 which `SampleBuffer` to use to render audio. If the first zone of an instrument does not end with a `sampleID`
 generator, then it is considered to be the one and only `global` zone, with its generators/modulators applied to all
 other zones unless a zone has its own definition.
 */
class Instrument : public WithCollectionBase<Zone::Instrument, Entity::Instrument>
{
public:
  using CollectionType = CollectionType;

  /**
   Construct new Instrument from SF2 entities

   @param file the SF2 file that was loaded
   @param config the SF2 file entity that defines the instrument
   */
  Instrument(const IO::File& file, const Entity::Instrument& config) noexcept;

  /**
   Locate the instrument zones that apply to the given key/velocity values.

   @param key the MIDI key number
   @param velocity the MIDI velocity value
   @returns vector of matching zones
   */
  CollectionType::Matches filter(int key, int velocity) const noexcept;
};

} // namespace SF2::Render
