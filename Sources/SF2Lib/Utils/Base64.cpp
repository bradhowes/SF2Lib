// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Utils/Base64.hpp"

using namespace SF2::Utils;

const int Base64::decoder[256] = {
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  0, 0, 0, 0, 0, 62, 63, 62, 62, 63, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5,
  6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 0, 0, 0, 0, 63, 0, 26, 27, 28, 29, 30,
  31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51
};

const char Base64::encoder[65] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string
Base64::decode(const unsigned char* ptr, size_t size) noexcept
{
  std::string source{reinterpret_cast<const char*>(ptr), size};
  return decode(source);
}

std::string
Base64::decode(const std::string& input) noexcept
{
  const char* in = input.data();
  auto inputSize = input.size();
  size_t padded = inputSize > 0 && (inputSize % 4 || in[inputSize - 1] == '=');
  const size_t commonSize = ((inputSize + 3) / 4 - padded) * 4;

  std::string output(commonSize / 4 * 3 + padded, '\0');
  auto out = output.data();

  for (auto end = in + commonSize; in < end; in += 4) {
    auto value = decoder[int(in[0])] << 18 | decoder[int(in[1])] << 12 | decoder[int(in[2])] << 6 | decoder[int(in[3])];
    *out++ = static_cast<char>(value >> 16);
    *out++ = static_cast<char>(value >> 8 & 0xFF);
    *out++ = static_cast<char>(value & 0xFF);
  }

  if (padded) {
    int value = decoder[int(in[0])] << 18 | decoder[int(in[1])] << 12;
    in += 2;
    output[output.size() - 1] = static_cast<char>(value >> 16);
    if (inputSize > commonSize + 2 && *in != '=') {
      value |= decoder[int(*in)] << 6;
      output.push_back(char(value >> 8 & 0xFF));
    }
  }

  return output;
}

std::string
Base64::encode(const std::string& input) noexcept
{
  auto inputSize = input.size();
  size_t outputSize = 4 * ((inputSize + 2) / 3);
  if (outputSize < inputSize) return std::string();

  std::string output;
  output.resize(outputSize);
  auto out = static_cast<char*>(&output[0]);
  auto in = input.data();

  while (inputSize >= 3) {
    *out++ = encoder[in[0] >> 2];
    *out++ = encoder[((in[0] & 0x03) << 4) | (in[1] >> 4)];
    *out++ = encoder[((in[1] & 0x0f) << 2) | (in[2] >> 6)];
    *out++ = encoder[in[2] & 0x3f];
    in += 3;
    inputSize -= 3;
  }

  if (inputSize > 0) {
    *out++ = encoder[in[0] >> 2];
    if (inputSize == 1) {
      *out++ = encoder[(in[0] & 0x03) << 4];
      *out++ = '=';
    }
    else {
      *out++ = encoder[((in[0] & 0x03) << 4) | (in[1] >> 4)];
      *out++ = encoder[(in[1] & 0x0f) << 2];
    }
    *out++ = '=';
  }

  return output;
}
