// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once
#include <os/log.h>

#include <list>
#include <vector>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/Utils/ListNodeAllocator.hpp"

namespace SF2::Render::Engine {

/**
 Least-recently used cache of active voices. All operations on the cache are O(1) but each entry in the
 cache is 3x the size of the value being held (`size_t`) + an iterator that points to the entry in the cache.
 Internally, the cache consists of a linked list which keeps the voices ordered by their time of activation. For fast
 removal within the linked list, there is a separate vector of iterators that points to each entry in the linked list.
 Changes to a std::list do not invalidate iterators that point to other nodes besides the one being added or removed.

 This vector is indexed by the voice index that is unique to each voice.

 The internal std::list uses a custom allocator that guarantees there are no allocations/frees during changes in the
 std::list container.
 */
class OldestActiveVoiceCache
{
public:
  using Allocator = Utils::ListNodeAllocator<size_t, 128>;
  using iterator = std::list<size_t, Allocator>::iterator;
  using const_iterator = std::list<size_t, Allocator>::const_iterator;

  /**
   Constructor. Allocates nodes in the cache for a maximum number of voices.

   @param maxVoiceCount the number of voices to support
   */
  OldestActiveVoiceCache(size_t maxVoiceCount) noexcept;

  /**
   Add a voice to the cache. It must not already be in the cache.

   @param voiceIndex the unique ID of the voice
   */
  void add(size_t voiceIndex) noexcept;

  /**
   Remove a voice from the cache. It must be in the cache.

   @param voiceIndex the unique ID of the voice
   */
  iterator remove(size_t voiceIndex) noexcept;

  /**
   Remove the oldest voice. There must be at least one active voice in the cache (really, the size of the list should
   be the same as the size of the vector).

   @returns index of the voice that was taken from the cache
   */
  size_t takeOldest() noexcept;

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
  std::list<size_t, Allocator> leastRecentlyUsed_;
  std::vector<std::list<size_t>::iterator> iterators_{};
  os_log_t log_;
};

} // end namespace SF2::Render::Engine
