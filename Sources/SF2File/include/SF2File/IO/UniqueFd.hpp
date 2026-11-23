// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <fcntl.h>
#include <unistd.h>

#include <utility>

namespace SF2::IO {

/**
 Owner of a POSIX file descriptor. Closes the descriptor when destroyed. Move-only, so there is always exactly one
 owner and a descriptor is never closed twice.
 */
class UniqueFd {
public:
  /// Construct an instance that owns nothing.
  UniqueFd() = default;

  /**
   Take ownership of a file descriptor.

   @param fd the descriptor to own. A negative value means "nothing".
   */
  explicit UniqueFd(int fd) noexcept : fd_{fd < 0 ? -1 : fd} {}

  /**
   Create an owner of a duplicate of a descriptor that belongs to someone else. The caller keeps ownership of `fd` and
   may close it at any time without affecting the duplicate.

   @param fd the descriptor to duplicate
   @returns new instance, which owns nothing if `fd` is invalid or could not be duplicated
   */
  static UniqueFd duplicate(int fd) noexcept { return UniqueFd(fd < 0 ? -1 : ::fcntl(fd, F_DUPFD_CLOEXEC, 0)); }

  /**
   Open a file read-only.

   @param path the path of the file to open
   @returns new instance, which owns nothing if the file could not be opened
   */
  static UniqueFd openForReading(const char* path) noexcept { return UniqueFd(::open(path, O_RDONLY | O_CLOEXEC)); }

  UniqueFd(const UniqueFd&) = delete;
  UniqueFd& operator=(const UniqueFd&) = delete;

  UniqueFd(UniqueFd&& rhs) noexcept : fd_{std::exchange(rhs.fd_, -1)} {}

  UniqueFd& operator=(UniqueFd&& rhs) noexcept {
    if (this != &rhs) reset(std::exchange(rhs.fd_, -1));
    return *this;
  }

  ~UniqueFd() { reset(); }

  /// @returns the owned descriptor, or -1 if there is none. Ownership is not transferred.
  int get() const noexcept { return fd_; }

  /// @returns true if a descriptor is owned
  bool isValid() const noexcept { return fd_ >= 0; }

  /**
   Close the owned descriptor (if any) and take ownership of another one.

   @param fd the new descriptor to own (default is none)
   */
  void reset(int fd = -1) noexcept {
    if (fd_ >= 0) ::close(fd_);
    fd_ = fd < 0 ? -1 : fd;
  }

private:
  int fd_{-1};
};

} // end namespace SF2::IO
