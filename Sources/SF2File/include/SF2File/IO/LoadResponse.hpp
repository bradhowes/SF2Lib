// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

namespace SF2::IO {

/**
 Result of loading an SF2 file. Defined on its own (and aliased as `File::LoadResponse`) so that the Swift-facing
 `Engine` headers can use it without exposing the whole `File` API to Swift.
 */
enum class LoadResponse: int {
  ok = 0,
  notFound = 1,
  invalidFormat = 2,
  none = -1
};

} // end namespace SF2::IO
