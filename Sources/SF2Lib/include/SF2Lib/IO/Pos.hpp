// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <unistd.h>

#include "SF2Lib/IO/Tag.hpp"
#include "SF2Lib/Types.hpp"

namespace SF2::IO {

class Chunk;
class ChunkList;

/**
 Representation of a file position. Instances of this type are immutable by design. It has methods that will generate
 instances with new position values.
 */
struct Pos {

  /**
   Constructor

   @param fd the file descriptor to read from
   @param pos the current location in the file being processed
   @param end the end of the file being processed
   */
  Pos(int fd, off_t pos, off_t end) noexcept;

  /// @returns a new ChunkList from the current position.
  ChunkList makeChunkList() const;

  /// @returns a new Chunk from the current position.
  Chunk makeChunk() const;

  /**
   Read bytes from the file at the current position and place them into the given buffer.

   @param buffer the destination for the bytes

   @returns new Pos instance for the next bytes in the file
   */
  template <EntityDerivedType T>
  Pos readInto(T& buffer) const { return readInto(&buffer, sizeof(buffer)); }

  /**
   Read bytes from the file at the current position and place them into the given buffer.

   @param buffer the destination for the bytes
   @param maxCount the maximum number of bytes to read, even if the size of the buffer is larger

   @returns new Pos instance for the next bytes in the file
   */
  template <EntityDerivedType T>
  Pos readInto(T& buffer, size_t maxCount) const { return readInto(&buffer, std::min(sizeof(buffer), maxCount)); }

  /**
   Read bytes from the file at the current position and place them into the given buffer.

   @param buffer the destination for the bytes
   @param count the number number of bytes to read

   @returns new Pos instance for the next bytes in the file
   */
  Pos readInto(void* buffer, size_t count) const;

  /// @returns the file offset represented by this instance
  off_t offset() const noexcept { return pos_; }

  /// @returns number of bytes available to read at this position in the file.
  off_t available() const noexcept { return end_ - pos_; }

  /**
   Calculate new Pos value after advancing `offset` bytes forward.

   @param offset the number of bytes to advance
   @returns new Pos instance for the next bytes in the file
   */
  Pos advance(off_t offset) const noexcept;

  /// @returns true if Pos is invalid
  explicit operator bool() const noexcept { return fd_ < 0 || pos_ >= end_; }

  /// @returns true if first Pos value is less than the second one
  friend bool operator <(const Pos& lhs, const Pos& rhs) noexcept { return lhs.pos_ < rhs.pos_; }

  /// Type of function to call to seek to a position in a file
  using SeekProcType = off_t (*)(int fd, off_t offset, int whence);

  /// Function to call to seek to a position in a file
  static SeekProcType SeekProc;

  /// Type of function to call to read from current position in a file
  using ReadProcType = ssize_t (*)(int fd, void* buffer, size_t size);

  /// Function to call to read from current position in a file
  static ReadProcType ReadProc;

  /// RAII struct for handling mocking of the Pos file IO methods. Only used for testing.
  struct Mockery {
    Mockery(SeekProcType seeker, ReadProcType reader) : seeker_{Pos::SeekProc}, reader_{Pos::ReadProc} {
      Pos::SeekProc = seeker;
      Pos::ReadProc = reader;
    }

    ~Mockery() {
      Pos::SeekProc = seeker_;
      Pos::ReadProc = reader_;
    }

  private:
    Pos::SeekProcType seeker_;
    Pos::ReadProcType reader_;
  };

private:
  static off_t seek(int fd, off_t offset, int whence) noexcept { return (*SeekProc)(fd, offset, whence); }
  static ssize_t read(int fd, void* buffer, size_t size) noexcept { return (*ReadProc)(fd, buffer, size); }

  int fd_;
  off_t pos_;
  off_t end_;
};

} // end namespace SF2::IO
