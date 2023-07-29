// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

/**
 Classes used to generate new samples from SF2 sample data for a given pitch and sample rate.
 */
namespace SF2::Render::Voice::Sample {

/**
 Represents the sample index bounds and loop start/end indices using values from the SF2 'shdr' entity as well as
 state values from generators that can change in real-time. Note that unlike the "absolute" values in the 'shdr' and
 the state offsets which are all based on the entire sample block of the file, these values are offsets from the first
 sample found in a NormalizedSampleSource.
 */
class Bounds {
public:
  using Index = Entity::Generator::Index;

  /**
   Construct Bounds using information from 'shdr' and current voice state values from generators related to
   sample indices.

   @param header the 'shdr' header to use
   @param state the generator values to use
   @returns new Bounds instance
   */
  static Bounds make(const Entity::SampleHeader& header, const State::State& state) noexcept {
    constexpr int coarse = 1 << 15;
    auto offset = [&state, coarse](Index fineIndex, Index courseIndex) -> int {
      return state.unmodulated(fineIndex) + state.unmodulated(courseIndex) * coarse;
    };

    // Calculate offsets for the samples using state generator values set by preset/instrument zones.
    auto startOffset = offset(Index::startAddressOffset, Index::startAddressCoarseOffset);
    auto startLoopOffset = offset(Index::startLoopAddressOffset, Index::startLoopAddressCoarseOffset);
    auto endLoopOffset = offset(Index::endLoopAddressOffset, Index::endLoopAddressCoarseOffset);
    auto endOffset = offset(Index::endAddressOffset, Index::endAddressCoarseOffset);

    // Don't trust values above. Clamp them to valid ranges before using.
    auto lower = int(header.startIndex());
    auto upper = int(header.endIndex());
    auto clampPos = [lower, upper](int value) -> size_t { return size_t(std::clamp(value, lower, upper) - lower); };

    return Bounds(clampPos(lower + startOffset),
                  clampPos(int(header.startLoopIndex()) + startLoopOffset),
                  clampPos(int(header.endLoopIndex()) + endLoopOffset),
                  clampPos(upper + endOffset));
  }

  Bounds() noexcept = default;

  /// @returns the index of the first sample to use for rendering
  constexpr size_t startPos() const noexcept { return startPos_; }
  /// @returns the index of the first sample of a loop
  constexpr size_t startLoopPos() const noexcept { return startLoopPos_; }
  /// @returns the index of the first sample AFTER a loop
  constexpr size_t endLoopPos() const noexcept { return endLoopPos_; }
  /// @returns the index after the last valid sample to use for rendering
  constexpr size_t endPos() const noexcept { return endPos_; }
  /// Number of samples involved in a loop
  constexpr size_t loopSize() const noexcept { return endLoopPos() - startLoopPos(); }
  /// True if there is a loop established for the samples
  constexpr bool hasLoop() const noexcept {
    return startLoopPos_ > startPos_ && startLoopPos_ < endLoopPos_ && endLoopPos_ <= endPos_;
  }

private:
  Bounds(size_t startPos, size_t startLoopPos, size_t endLoopPos, size_t endPos) noexcept :
  startPos_{startPos}, startLoopPos_{startLoopPos}, endLoopPos_{endLoopPos}, endPos_{endPos} {}

  size_t startPos_{0};
  size_t startLoopPos_{0};
  size_t endLoopPos_{0};
  size_t endPos_{0};
};

} // namespace SF2::Render::Sample
