// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once
#include <os/log.h>

#include <list>
#include <memory_resource>
#include <vector>

#include "SF2Lib/Types.hpp"

namespace SF2::Render::Engine {

/**
 Least-recently used cache of active voices. All operations on the cache are O(1) but each entry in the
 cache is 3x the size of the value being held (`size_t`) + an iterator that points to the entry in the cache.
 Internally, the cache consists of a linked list which keeps the voices ordered by their time of activation. For fast
 removal within the linked list, there is a separate vector of iterators that points to each entry in the linked list.
 Changes to a std::list do not invalidate iterators that point to other nodes besides the one being added or removed.

 This vector is indexed by the voice index that is unique to each voice.

 The internal std::pmr::list uses a fixed-sized PMR allocator that guarantees there are no allocations/frees during
 changes in the std::pmr::list container.
 */
template <size_t MaxVoiceCount>
class OldestActiveVoiceCache
{
public:
  static inline constexpr size_t maxVoiceCount_ = MaxVoiceCount;

  using iterator = std::pmr::list<size_t>::iterator;
  using const_iterator = std::pmr::list<size_t>::const_iterator;

  /**
   Constructor. Allocates nodes in the cache for a maximum number of voices.
   */
  OldestActiveVoiceCache() noexcept
  : iterators_(maxVoiceCount_, leastRecentlyUsed_.end()), log_{os_log_create("SF2Lib", "OldestActiveVoiceCache")}
  {
    ;
  }

  /**
   Add a voice to the cache. It must not already be in the cache.

   @param voiceIndex the unique ID of the voice
   */
  void add(size_t voiceIndex) noexcept
  {
    iterators_[voiceIndex] = leastRecentlyUsed_.insert(leastRecentlyUsed_.begin(), voiceIndex);
  }

  /**
   Remove a voice from the cache. It must be in the cache.

   @param voiceIndex the unique ID of the voice

   @returns iterator of the voice slot that was removed
   */
  iterator remove(size_t voiceIndex) noexcept
  {
    auto pos = leastRecentlyUsed_.erase(iterators_[voiceIndex]);
    iterators_[voiceIndex] = leastRecentlyUsed_.end();
    return pos;
  }

  /**
   Remove the oldest voice. There must be at least one active voice in the cache (really, the size of the list should
   be the same as the size of the vector).

   @returns index of the voice that was taken from the cache
   */
  size_t takeOldest() noexcept
  {
    size_t oldest = leastRecentlyUsed_.back();
    iterators_[oldest] = leastRecentlyUsed_.end();
    leastRecentlyUsed_.pop_back();
    return oldest;
  }

  /// @returns true if the cache is empty
  bool empty() const noexcept { return leastRecentlyUsed_.empty(); }

  /// @returns the number of voices in the cache (since C++11 this is guaranteed to be O(1)).
  size_t size() const noexcept { return leastRecentlyUsed_.size(); }

  /// @returns iterator to first (oldest) active voice
  iterator begin() noexcept { return leastRecentlyUsed_.begin(); }

  /// @returns iterator to last + 1 voice
  iterator end() noexcept { return leastRecentlyUsed_.end(); }

  /// @returns iterator to first (oldest) active voice
  const_iterator cbegin() const noexcept { return leastRecentlyUsed_.cbegin(); }

  /// @returns iterator to last + 1 voice
  const_iterator cend() const noexcept { return leastRecentlyUsed_.cend(); }

  /// Remove all active entries.
  void clear() noexcept { while (!empty()) takeOldest(); }

private:
  std::array<std::byte, MaxVoiceCount * sizeof(size_t) * 8> buffer_; // TODO: calculate proper size
  std::pmr::monotonic_buffer_resource mbr_{buffer_.data(), buffer_.size(), std::pmr::null_memory_resource()};
  std::pmr::unsynchronized_pool_resource pr_{&mbr_};
  std::pmr::polymorphic_allocator<size_t> allocator_{&pr_};
  std::pmr::list<size_t> leastRecentlyUsed_{allocator_};
  std::pmr::vector<iterator> iterators_{};
  os_log_t log_;
};

} // end namespace SF2::Render::Engine
