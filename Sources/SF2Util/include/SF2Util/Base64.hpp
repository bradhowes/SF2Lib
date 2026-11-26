#pragma once

#include <cstdint>
#include <optional>
#include <span>
#include <string>
#include <vector>

namespace SF2::Utils {

/**
 Base64 routines. Follows RFC 4648 section 4 with mandatory padding ('=').
 */
struct Base64 {
  /**
   Convert given string from Base-64 to vector of unsigned bytes.

   @param encoded_str the Base64-encoded string
   @returns converted byte sequence
   */
  static std::optional<std::vector<std::uint8_t>> decode(std::string_view encoded_str);

  /**
   Convert the given sequence of unsigned bytes into a Base-64 string.

   @param input the contents to convert
   @returns Base-64 character sequence
   */
  static std::string encode(std::span<std::uint8_t const> input);

  /**
   Convert the given sequence of unsigned bytes into a Base-64 string.

   @param input the contents to convert
   @returns Base-64 character sequence
   */
  static std::string encode(std::string_view input);
};

} // end namespace SF2::Utils
