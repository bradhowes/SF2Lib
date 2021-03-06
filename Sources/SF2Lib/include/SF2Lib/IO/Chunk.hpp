// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <algorithm>
#include <memory>
#include <vector>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/IO/Format.hpp"
#include "SF2Lib/IO/Pos.hpp"
#include "SF2Lib/IO/StringUtils.hpp"
#include "SF2Lib/IO/Tag.hpp"

namespace SF2::IO {

/**
 Represents a tagged chunk of a file. A chunk starts with a 4-byte value that is taken as 4
 ASCII characters. The 4-byte value uniquely identifies the type of data held in the chunk.
 The next entry in the chunk layout is an unsigned 4-byte value indicating the number of
 bytes in the chunk. The chunk records the position of its data in the file.
 It does not hold any internal data apart from the chunk tag and size.
 */
class Chunk {
public:

  /**
   Constructor

   @param tag the chunk's Tag type
   @param size the number of bytes held by the chunk
   @param pos the file position where the contents of the chunk is to be found
   */
  Chunk(Tag tag, uint32_t size, Pos pos) noexcept : tag_{tag}, size_{size}, pos_{pos} {}

  /**
   Obtain the Tag type for the chunk

   @return Tag type
   */
  Tag tag() const noexcept { return tag_; }

  /**
   Obtain the size of the chunk data

   @return Tag type
   */
  size_t size() const noexcept { return size_; }

  /**
   Obtain the location of the first byte of the chunk data

   @return Pos instance
   */
  Pos begin() const noexcept { return pos_; }

  /**
   Obtain the location right after the last byte of chunk data

   @return Pos instance
   */
  Pos end() const noexcept { return pos_.advance(size_); }

  /** Obtain the file position of the next chunk in the file after this one.

   @return Pos instance
   */
  Pos advance() const noexcept { return pos_.advance(paddedSize()); }

  /**
   Treat the chunk data as a string of ASCII characters with a max length of 256 characters. The result is sanitized:
   leading/trailing spaces are removed, non-ASCII characters are converted to '_' (the SF2 spec is pre-Unicode).

   @return chunk contents as std::string value
   */
  std::string extract() const noexcept {
    char buffer[256];
    size_t count = std::min(size(), sizeof(buffer));
    begin().readInto(buffer, count);
    buffer[count - 1] = 0;
    trim_property(buffer);
    return std::string(buffer);
  }

  /**
   Read samples into a buffer.

   @param buffer to hold the 16-bit audio samples
   */
  void extractSamples(std::vector<int16_t>& buffer) const noexcept {
    buffer.resize(size() / sizeof(int16_t), 0);
    begin().readInto(buffer.data(), size());
  }

private:
  uint32_t paddedSize() const noexcept { return size_ + (size_ & 1); }

  Tag const tag_;
  uint32_t const size_;
  Pos const pos_;
};

} // end namespace SF2::IO
