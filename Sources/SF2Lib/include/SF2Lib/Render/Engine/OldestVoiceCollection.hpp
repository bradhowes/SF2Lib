// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once
#include <os/log.h>

#include <list>
#include <memory_resource>
#include <vector>

#include "SF2Lib/Types.hpp"

namespace SF2::Render::Engine {

/**
 Least-recently used collection of voice indices. All operations on the cache are O(1) and there is no memory allocation
 after construction. Internally, the cache consists of a linked list which keeps the voices ordered by their time of
 activation, newest at `begin())` to oldest just before `end()`. For fast removal within the linked list, there is a
 separate vector of iterators that points to each entry in the linked list. Changes to a `std::list` do not invalidate
 iterators that point to other nodes besides the one being added or removed.
 */
template <size_t MaxVoiceCount>
class OldestVoiceCollection
{
public:
  using iterator = std::pmr::list<size_t>::iterator;
  using const_iterator = std::pmr::list<size_t>::const_iterator;

  /**
   Constructor. Allocates nodes in the cache for a maximum number of voices.

   @param voiceCount the number of voices to hold in the collection. Must be <= `MaxVoiceCount`.
   */
  OldestVoiceCollection(size_t voiceCount) noexcept
  : slots_(voiceCount, leastRecentlyUsed_.end()), log_{os_log_create("SF2Lib", "OldestActiveVoiceCache")}
  {
    for (size_t voiceIndex = 0; voiceIndex < voiceCount; ++voiceIndex) {
      slots_[voiceIndex] = leastRecentlyUsed_.emplace(leastRecentlyUsed_.begin(), voiceIndex);
    }
    active_ = 0;
    partition_ = leastRecentlyUsed_.begin();
  }

  /**
   Remove the oldest voice to use for a new note ON request. Note that it may be an active voice, but it is guaranteed
   to be the oldest voice in the collection.

   @returns index of the voice
   */
  size_t voiceOn() noexcept
  {
    // Get the oldest voice index
    size_t voiceIndex = leastRecentlyUsed_.back();
    auto wasLastActive = partition_ == slots_[voiceIndex];
    leastRecentlyUsed_.pop_back();

    // Make it the newest
    slots_[voiceIndex] = leastRecentlyUsed_.emplace(leastRecentlyUsed_.begin(), voiceIndex);

    if (active_ < slots_.size()) ++active_;
    if (wasLastActive) partition_ = leastRecentlyUsed_.end();

    std::clog << "voiceOn: " << voiceIndex << std::endl;
    return voiceIndex;
  }

  iterator voiceOff(size_t voiceIndex) noexcept {
    std::clog << "voiceOff: " << voiceIndex << std::endl;
    assert(active_ > 0);
    --active_;
    // Remove voice from list
    auto next = leastRecentlyUsed_.erase(slots_[voiceIndex]);
    // Make it the oldest
    auto isFirstInactive = partition_ == leastRecentlyUsed_.end();
    slots_[voiceIndex] = leastRecentlyUsed_.emplace(leastRecentlyUsed_.end(), voiceIndex);

    // Point to the first inactive voice index
    if (isFirstInactive) partition_ = slots_[voiceIndex];

    // Return the element following the one that was removed
    return next;
  }

  /// @returns the number of voices in the collection
  size_t size() const noexcept { return slots_.size(); }

  bool empty() const noexcept { return active_ == 0; }

  /// @returns the number of active voices
  size_t active() const noexcept { return active_; }

  /// @returns iterator to first active voice
  iterator begin() noexcept { return leastRecentlyUsed_.begin(); }

  /// @returns iterator to the first inactive voice, which is always the first voice after the last active one.
  iterator end() noexcept { return partition_; }

  /// @returns iterator to first active voice
  const_iterator begin() const noexcept { return leastRecentlyUsed_.begin(); }

  /// @returns iterator to the first inactive voice, which is always the first voice after the last active one.
  const_iterator end() const noexcept { return partition_; }

private:
  // TODO: calculate proper size -- testing found this sufficient for a MaxVoiceCount of 96.
  static constexpr size_t BufferSize = 1024 * 4 + 168;

  std::array<std::byte, BufferSize> buffer_;
  std::pmr::monotonic_buffer_resource mbr_{buffer_.data(), buffer_.size(), std::pmr::null_memory_resource()};
  std::pmr::unsynchronized_pool_resource pr_{&mbr_};
  std::pmr::polymorphic_allocator<size_t> allocator_{&pr_};

  std::pmr::list<size_t> leastRecentlyUsed_{allocator_};
  std::pmr::vector<iterator> slots_{allocator_};
  size_t active_;
  iterator partition_;
  os_log_t log_;
};

} // end namespace SF2::Render::Engine
