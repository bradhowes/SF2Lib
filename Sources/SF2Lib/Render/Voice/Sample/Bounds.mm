// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"

using namespace SF2::Render::Voice::Sample;

const os_log_t Bounds::log_{Log::create("Bounds")};

Bounds::Bounds(size_t startPos, size_t startLoopPos, size_t endLoopPos, size_t endPos) noexcept
  : startPos_{startPos}, startLoopPos_{startLoopPos}, endLoopPos_{endLoopPos}, endPos_{endPos}
{
  hasLoop_ = startLoopPos_ > startPos_ && startLoopPos_ < endLoopPos_ && endLoopPos_ <= endPos_;
  os_log_debug(log_, "init - start: %ld startLoop: %ld endLoop: %ld end: %ld hasLoop: %d",
               startPos_, startLoopPos_, endLoopPos_, endPos_, hasLoop_);
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

  os_log_debug(log_, "make - start: %d startLoop: %d endLoop: %d end: %d",
               startOffset, startLoopOffset, endLoopOffset, endOffset);

  // Don't trust values above. Clamp them to valid range before using, and convert to use `header.startIndex()` as their origin.
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
