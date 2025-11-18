// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <unistd.h>

namespace SF2::IO {

/**
 Manage a file descriptor that was opened elsewhere so that when the `Closure` instance is destroyed, the held
 file descriptor is closed.
 */
struct Closer
{
  /**
   Constructor that takes ownership of the given file descriptor.

   @param fd the file descriptor to manage
   */
  explicit Closer(int fd) : fd_{fd} {}

  /**
   Destructor that closes the held file descriptor if it is valid.
   */
  ~Closer() { if (is_valid()) ::close(fd_); }

  /// @returns the held file descriptor
  inline int operator *() const { return fd_; }

  /// @returns true if the held file descriptor is valid
  inline bool is_valid() const { return fd_ != -1; }

private:
  int fd_;
};

} // end namespace SF2::IO
