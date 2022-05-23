#pragma once

#include <cstddef>
#include <iostream>
#include <memory>
#include <limits>

namespace SF2::Utils {

/**
 Custom allocator for the OldestActiveVoiceCache for the list nodes. We allocate all nodes that we will
 ever need and then keep them when list deallocates them. This is so that we do not incur any memory
 allocations when voices change while we are rendering.
 */
class Base64 {
public:

  inline static const int decoding[256] = { 0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
    0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 62, 63, 62, 62, 63, 52, 53, 54, 55,
    56, 57, 58, 59, 60, 61,  0,  0,  0,  0,  0,  0,  0,  0,  1,  2,  3,  4,  5,  6,
    7,  8,  9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25,  0,
    0,  0,  0, 63,  0, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
    41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51
  };

  inline static const unsigned char encoding[65] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

  inline static std::string decode(const unsigned char* ptr, size_t size) noexcept {
    std::string source{reinterpret_cast<const char*>(ptr), size};
    return decode(source);
  }

  inline static std::string decode(const std::string& data) noexcept {
    const char* p = data.data();
    auto size = data.size();
    size_t pad = size > 0 && (size % 4 || p[size - 1] == '=');
    const size_t L = ((size + 3) / 4 - pad) * 4;
    std::string str(L / 4 * 3 + pad, '\0');

    for (size_t i = 0, j = 0; i < L; i += 4) {
      auto n = decoding[p[i]] << 18 | decoding[p[i + 1]] << 12 | decoding[p[i + 2]] << 6 | decoding[p[i + 3]];
      str[j++] = static_cast<char>(n >> 16);
      str[j++] = static_cast<char>(n >> 8 & 0xFF);
      str[j++] = static_cast<char>(n & 0xFF);
    }

    if (pad) {
      int n = decoding[p[L]] << 18 | decoding[p[L + 1]] << 12;
      str[str.size() - 1] = static_cast<char>(n >> 16);
      if (size > L + 2 && p[L + 2] != '=') {
        n |= decoding[p[L + 2]] << 6;
        str.push_back(char(n >> 8 & 0xFF));
      }
    }

    return str;
  }

  inline static std::string encode(const std::string& data) noexcept {
    const auto len = data.size();
    size_t olen = 4 * ((len + 2) / 3); /* 3-byte blocks to 4-byte */
    if (olen < len) return std::string(); /* integer overflow */

    std::string outStr;
    outStr.resize(olen);
    auto out = (unsigned char*)&outStr[0];

    auto end = data.data() + len;
    auto in = data.data();
    auto pos = out;
    
    while (end - in >= 3) {
      *pos++ = encoding[in[0] >> 2];
      *pos++ = encoding[((in[0] & 0x03) << 4) | (in[1] >> 4)];
      *pos++ = encoding[((in[1] & 0x0f) << 2) | (in[2] >> 6)];
      *pos++ = encoding[in[2] & 0x3f];
      in += 3;
    }

    if (end - in) {
      *pos++ = encoding[in[0] >> 2];
      if (end - in == 1) {
        *pos++ = encoding[(in[0] & 0x03) << 4];
        *pos++ = '=';
      }
      else {
        *pos++ = encoding[((in[0] & 0x03) << 4) | (in[1] >> 4)];
        *pos++ = encoding[(in[1] & 0x0f) << 2];
      }
      *pos++ = '=';
    }

    return outStr;
  }
};

} // end namespace SF2::Utils
