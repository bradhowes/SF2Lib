// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

namespace SF2::IO { struct Pos; }

/**
 Collection of types that mirror data structures defined in the SF2 spec. These are all read-only representations.
 */
namespace SF2::Entity {

/**
 Base class that offers common functionality for working with entities that are part of a collection.
 */
struct Entity {
  
  /**
   Calculate the number of bag elements between to items
   
   @param next the bag index from the following item in the collection
   @param current the bag index from the current item in the collection
   */
  static uint16_t calculateSize(uint16_t next, uint16_t current) noexcept { return next - current; }
};

} // end namespace SF2::Entity
