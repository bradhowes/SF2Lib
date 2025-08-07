// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <unistd.h>

namespace SF2::IO {

/**
 Manage a file descriptor that was opened elsewhere. If still held upon destruction, close it. This is currently used
 to track close a file descriptor due to an exception that exits the scope that contains the Closer instance.
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

  /// returns the held file descriptor
  int operator *() const { return fd_; }

  /// returns true if the held file descriptor is not -1
  bool is_valid() const { return fd_ != -1; }

  /**
   Release ownership of the held file descriptor.

   @returns the file descriptor
   */
  int release() noexcept {
    int tmp = -1;
    std::swap(tmp, fd_);
    return tmp;
  }

private:
  int fd_{-1};
};

} // end namespace SF2::IO
