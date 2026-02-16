// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once
#include <os/log.h>

#include <list>
#include <memory_resource>
#include <vector>

#include "SF2Lib/Render/Engine/Traits.hpp"
#include "SF2Lib/Render/Engine/Traits.hpp"
#include "SF2Util/Types.hpp"

namespace SF2::Render::Engine {

/**
 Least-recently used collection of voice indices. All operations on the cache are O(1) and there is no memory allocation
 after construction. Internally, the cache consists of a linked list which keeps the active voices ordered by their time of
 activation, newest at `begin())` to oldest just before `end()`. For fast removal within the linked list, there is a
 separate vector of iterators that points to each entry in the linked list. Changes to a `std::list` do not invalidate
 iterators that point to other nodes besides the one being added or removed.
 */
class OldestVoiceCollection
{
public:
  using iterator = std::pmr::list<size_t>::iterator;
  using const_iterator = std::pmr::list<size_t>::const_iterator;

  /**
   Constructor. Allocates nodes in the cache for a maximum number of voices.
   */
  OldestVoiceCollection() noexcept
  {
    for (size_t voiceIndex = 0; voiceIndex < traits::maxVoiceCount; ++voiceIndex) {
      slots_[voiceIndex] = leastRecentlyUsed_.emplace(leastRecentlyUsed_.begin(), voiceIndex);
    }

    // All voices are inactive at the start.
    firstInactiveVoice_ = leastRecentlyUsed_.begin();
  }

  /**
   Remove the index of the oldest voice to use for a new note ON request. Note that it may be an active voice, but it is guaranteed
   to be the oldest voice in the collection.

   @returns index of the voice
   */
  size_t voiceAcquire() noexcept
  {
    // Get the oldest (LRU) voice index.
    size_t voiceIndex = leastRecentlyUsed_.back();

    // When `true` there are no inactive voices -- all are active and rendering
    auto tookFirstInactiveVoice = firstInactiveVoice_ == slots_[voiceIndex];
    leastRecentlyUsed_.pop_back();

    // Make it the newest
    slots_[voiceIndex] = leastRecentlyUsed_.emplace(leastRecentlyUsed_.begin(), voiceIndex);

    if (activeVoiceCounter_ < slots_.size()) {
      ++activeVoiceCounter_;
    }

    if (tookFirstInactiveVoice) {
      firstInactiveVoice_ = leastRecentlyUsed_.end();
    }

    return voiceIndex;
  }

  /**
   Add a voice index to the pool of available voices. NOTE: this should *only* be called when `voiceIndex` is guaranteed to be
   for an active voice such as in a loop iterating between `begin()` and `end()`. This is currently the case with `Engine` logic
   and this constraint must be maintained.

   @param voiceIndex the index to add
   */
  iterator voiceRelease(size_t voiceIndex) noexcept {

    if (activeVoiceCounter_ == 0) {
      os_log_error(log_, "voiceRelease - logic error: voiceRelease(%lu) called while active voice count is zero", voiceIndex);
      return firstInactiveVoice_;
    }

    --activeVoiceCounter_;

    // Remove voice from list
    auto next = leastRecentlyUsed_.erase(slots_[voiceIndex]);

    // Make it the oldest
    auto isFirstInactive = firstInactiveVoice_ == leastRecentlyUsed_.end();
    slots_[voiceIndex] = leastRecentlyUsed_.emplace(leastRecentlyUsed_.end(), voiceIndex);

    // Point to the first inactive voice index
    if (isFirstInactive) firstInactiveVoice_ = slots_[voiceIndex];

    // Return the element following the one that was removed
    return next;
  }

  /// @returns the number of voices in the collection
  size_t size() const noexcept { return slots_.size(); }

  bool empty() const noexcept { return activeVoiceCounter_ == 0; }

  /// @returns the number of active voices
  size_t activeVoiceCount() const noexcept { return activeVoiceCounter_; }

  /// @returns iterator to first (newest) active voice
  iterator begin() noexcept { return leastRecentlyUsed_.begin(); }

  /// @returns iterator to the first inactive voice, which is always the first voice after the oldest active one.
  iterator end() noexcept { return firstInactiveVoice_; }

  /// @returns iterator to first (newest) active voice
  const_iterator begin() const noexcept { return leastRecentlyUsed_.begin(); }

  /// @returns iterator to the first inactive voice, which is always the first voice after the oldest active one.
  const_iterator end() const noexcept { return firstInactiveVoice_; }

private:
  // TODO: calculate proper size -- testing found this sufficient for a MaxVoiceCount of 96.
  // static constexpr size_t BufferSize = 1024 * 4 + 168;
  // TODO: calculate proper size -- testing found this sufficient for a MaxVoiceCount of 128.
  static constexpr size_t BufferSize = 1024 * 6 + 128; // 168;

  std::array<std::byte, BufferSize> buffer_{};

  std::pmr::monotonic_buffer_resource mbr_{buffer_.data(), buffer_.size(), std::pmr::null_memory_resource()};
  std::pmr::unsynchronized_pool_resource pr_{&mbr_};
  std::pmr::polymorphic_allocator<size_t> allocator_{&pr_};

  std::pmr::list<size_t> leastRecentlyUsed_{allocator_};
  std::array<iterator, traits::maxVoiceCount> slots_{};

  size_t activeVoiceCounter_{0};

  // The first inactive voice. This is only used to mark the range of active voices (it is the value returned by `end()`)
  iterator firstInactiveVoice_;

  const os_log_t log_{Log::create("OldestVoiceCollection")};
};

} // end namespace SF2::Render::Engine
