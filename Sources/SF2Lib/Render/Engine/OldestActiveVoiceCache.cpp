// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Render/Engine/OldestActiveVoiceCache.hpp"

using namespace SF2::Render::Engine;

OldestActiveVoiceCache::OldestActiveVoiceCache(size_t maxVoiceCount) noexcept
: leastRecentlyUsed_(Allocator(maxVoiceCount)), log_{os_log_create("SF2Lib", "OldestActiveVoiceCache")}
{
  iterators_.assign(maxVoiceCount, leastRecentlyUsed_.end());
}

void
OldestActiveVoiceCache::add(size_t voiceIndex) noexcept
{
  assert(voiceIndex < iterators_.size());
  assert(iterators_[voiceIndex] == leastRecentlyUsed_.end());
  iterators_[voiceIndex] = leastRecentlyUsed_.insert(leastRecentlyUsed_.begin(), voiceIndex);
}

OldestActiveVoiceCache::iterator
OldestActiveVoiceCache::remove(size_t voiceIndex) noexcept
{
  assert(voiceIndex < iterators_.size());
  assert(iterators_[voiceIndex] != leastRecentlyUsed_.end());
  auto pos = leastRecentlyUsed_.erase(iterators_[voiceIndex]);
  iterators_[voiceIndex] = leastRecentlyUsed_.end();
  return pos;
}

size_t
OldestActiveVoiceCache::takeOldest() noexcept
{
  assert(!leastRecentlyUsed_.empty());
  size_t oldest = leastRecentlyUsed_.back();
  iterators_[oldest] = leastRecentlyUsed_.end();
  leastRecentlyUsed_.pop_back();
  return oldest;
}