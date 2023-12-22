// Copyright © 2022 Brad Howes. All rights reserved.

#include <os/log.h>

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
  iterators_[voiceIndex] = leastRecentlyUsed_.insert(leastRecentlyUsed_.begin(), voiceIndex);
}

OldestActiveVoiceCache::iterator
OldestActiveVoiceCache::remove(size_t voiceIndex) noexcept
{
  auto pos = leastRecentlyUsed_.erase(iterators_[voiceIndex]);
  iterators_[voiceIndex] = leastRecentlyUsed_.end();
  return pos;
}

size_t
OldestActiveVoiceCache::takeOldest() noexcept
{
  size_t oldest = leastRecentlyUsed_.back();
  iterators_[oldest] = leastRecentlyUsed_.end();
  leastRecentlyUsed_.pop_back();
  return oldest;
}
