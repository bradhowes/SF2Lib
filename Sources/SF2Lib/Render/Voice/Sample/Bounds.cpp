// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"

using namespace SF2::Render::Voice::Sample;

Bounds::Bounds(size_t startPos, size_t startLoopPos, size_t endLoopPos, size_t endPos) noexcept :
startPos_{startPos},
startLoopPos_{startLoopPos},
endLoopPos_{endLoopPos},
endPos_{endPos}
{
  ;
}

Bounds
Bounds::make(const Entity::SampleHeader& header, const State::State& state) noexcept
{
  constexpr int coarse = 1 << 15;
  auto offset = [&state](Index fineIndex, Index courseIndex) -> int {
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
  auto clampPos = [lower, upper](int value) -> size_t {
    return static_cast<size_t>(std::clamp(value, lower, upper) - lower);
  };

  return Bounds(clampPos(lower + startOffset),
                clampPos(int(header.startLoopIndex()) + startLoopOffset),
                clampPos(int(header.endLoopIndex()) + endLoopOffset),
                clampPos(upper + endOffset));
}

