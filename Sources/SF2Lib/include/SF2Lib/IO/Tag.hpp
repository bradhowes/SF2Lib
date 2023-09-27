// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <string>

#include "SF2Lib/Types.hpp"

namespace SF2::IO {

constexpr uint32_t Pack4Chars(const char* c) noexcept
{
  auto bits = [](char v, int shift) -> auto { return uint32_t(v) << shift; };
  return bits(c[3], 24) | bits(c[2], 16) | bits(c[1], 8) | bits(c[0], 0);
}

/**
 Global list of all tags defined in the SF2 specification.
 */
enum struct Tags : uint32_t {
  riff = Pack4Chars("RIFF"), // RIFF container
  sfbk = Pack4Chars("sfbk"), // soundfont block
  list = Pack4Chars("LIST"), // generic list
  info = Pack4Chars("INFO"),
  sdta = Pack4Chars("sdta"), // sample binary data

  pdta = Pack4Chars("pdta"), // preset, instrument, and sample header data
  ifil = Pack4Chars("ifil"),
  isng = Pack4Chars("isng"),
  inam = Pack4Chars("INAM"),
  irom = Pack4Chars("irom"), // info ids (1st byte of info strings

  iver = Pack4Chars("iver"),
  icrd = Pack4Chars("ICRD"),
  ieng = Pack4Chars("IENG"),
  iprd = Pack4Chars("IPRD"), // more info ids
  icop = Pack4Chars("ICOP"),

  icmt = Pack4Chars("ICMT"),
  istf = Pack4Chars("ISTF"), // and yet more info ids
  snam = Pack4Chars("snam"), // sample name
  smpl = Pack4Chars("smpl"), // binary samples
  phdr = Pack4Chars("phdr"), // preset definition

  pbag = Pack4Chars("pbag"), // collection of generators and modulators for a preset
  pmod = Pack4Chars("pmod"), // preset modulators
  pgen = Pack4Chars("pgen"), // preset generators including preset IDs
  inst = Pack4Chars("inst"), // instrument definition
  ibag = Pack4Chars("ibag"), // collection of generators and modulators for an instrument

  imod = Pack4Chars("imod"), // instrumen modulators
  igen = Pack4Chars("igen"), // instrument generators including reference to sample IDs
  shdr = Pack4Chars("shdr"), // sample info
  sm24 = Pack4Chars("sm24"), // sample extensions for 24-bit audio
  unkn = Pack4Chars("????"),
};

/**
 Each RIFF chunk or blob has a 4-character tag that uniquely identifies the contents of the chunk. This is also a 4-byte
 unsigned integer.
 */
class Tag {
public:

  /**
   Construct new Tag from an unsigned integer.

   @param tag the value to use
   */
  Tag(uint32_t tag) noexcept : tag_{tag} {}

  /**
   Construct new tag from a Tags enum value.

   @param tag the value to use
   */
  Tag(Tags tag) noexcept : tag_{SF2::valueOf(tag)} {}

  /// @returns the underlying raw value of the tag
  uint32_t rawValue() const noexcept { return tag_; }

  /// @returns Tags enum  value for this tag
  Tags toTags() const noexcept { return Tags(tag_); }

  /// @returns the 4-character text representation of the tag
  std::string toString() const noexcept { return std::string(reinterpret_cast<char const*>(&tag_), 4); }

  /**
   Compare another Tag instance with this one for equality.

   @param rhs the other value to compare against
   @returns true if the same
   */
  bool operator ==(const Tag& rhs) const noexcept { return tag_ == rhs.tag_; }

  /**
   Compare another Tag instance with this one for inequality.

   @param rhs the other value to compare against
   @returns true if not the same
   */
  bool operator !=(const Tag& rhs) const noexcept { return tag_ != rhs.tag_; }

private:
  uint32_t tag_;
};

} // end namespace SF2::IO
