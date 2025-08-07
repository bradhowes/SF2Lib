#pragma once

#include <cstddef>
#include <iostream>
#include <memory>
#include <limits>

namespace SF2::Utils {

/**
 Base64 routines. Follows RFC 4648 section 4 with mandatory padding ('=').
 */
struct Base64 {

  /**
   Convert given string from Base-64 to ASCII/UTF-8.

   @param ptr start of the text sequence
   @param size the number of characters to decode

   @returns converted character sequence
   */
  static std::string decode(const unsigned char* ptr, size_t size) noexcept;

  /**
   Convert the given string from Base-64 to ASCII/UTF-8.

   @param input the string to convert

   @returns converted character sequence
   */
  static std::string decode(const std::string& input) noexcept;

  /**
   Convert the given string to Base-64.

   @param input the string to convert

   @returns Base-64 character sequence
   */
  static std::string encode(const std::string& input) noexcept;

private:
  static const int decoder[256];
  static const char encoder[65];
};

} // end namespace SF2::Utils
