// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>

#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2File/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

/**
 Classes used to generate new samples from SF2 sample data for a given pitch and sample rate.
 */
namespace SF2::Render::Voice::Sample {

/**
 Represents the sample index bounds and loop start/end indices using values from the SF2 'shdr' entity as well as state values from
 generators that can change in real-time.
 */
class Bounds {
public:
  using Index = Entity::Generator::Index;

  /**
   Construct Bounds using information from 'shdr' and current voice state values from generators related to
   sample indices. The position values from 'shrd' refer to offsets from the start of the sample section of the source sound font
   file. The `\*Pos` attributes for `Bounds` are offsets from the first sample value used by an instrument.

   @param header the 'shdr' header to use
   @param state the generator values to use
   @returns new Bounds instance
   */
  static Bounds make(const Entity::SampleHeader& header, const State::State& state) noexcept;

  Bounds() = default;

  /// @returns the index of the first sample to use for rendering
  inline size_t startPos() const noexcept { return startPos_; }
  /// @returns the index of the first sample of a loop
  inline size_t startLoopPos() const noexcept { return startLoopPos_; }
  /// @returns the index of the first sample AFTER a loop
  inline size_t endLoopPos() const noexcept { return endLoopPos_; }
  /// @returns the index after the last valid sample to use for rendering
  inline size_t endPos() const noexcept { return endPos_; }
  /// Number of samples involved in a loop
  inline size_t loopSize() const noexcept { return endLoopPos() - startLoopPos(); }
  /// True if there is a loop established for the samples
  inline bool hasLoop() const noexcept { return hasLoop_; }

private:
  Bounds(size_t startPos, size_t startLoopPos, size_t endLoopPos, size_t endPos) noexcept;

  size_t startPos_{0};
  size_t startLoopPos_{0};
  size_t endLoopPos_{0};
  size_t endPos_{0};
  bool hasLoop_;

  static const os_log_t log_;
};

} // namespace SF2::Render::Sample
