// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include "SF2File/IO/Chunk.hpp"

namespace SF2::IO {

/**
 Like `Chunk`, this class represents a tagged chunk of a file, but this is also a collection of similar items all with
 the same `kind` tagged 4-byte value. See `ChunkItems` for a collection container that wraps a value of this type to
 provide an array of items from the tagged chunk.
 */
class ChunkList : public Chunk {
public:
  /**
   Constructor

   @param tag the container's Tag type
   @param size the number of bytes used by the chunk list
   @param kind the Tag type for the elements in the chunk list
   @param pos the file position where the first item in the list is to be found
   */
  ChunkList(Tag tag, uint32_t size, Tag kind, Pos pos);

  /// @returns the Tag type for the elements held in the container
  inline Tag kind() const noexcept { return kind_; }

private:
  Tag kind_;
};

} // end namespace SF2::IO
