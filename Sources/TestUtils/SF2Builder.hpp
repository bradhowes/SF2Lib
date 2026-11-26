// Copyright © 2026 Brad Howes. All rights reserved.

#pragma once

#include <cmath>
#include <cstdint>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <vector>

/**
 Builds small SF2 files in memory for tests and fuzzing. `minimal()` gives a valid file with one preset that uses one
 instrument that plays one looped sine-wave sample. Tests then change individual fields to produce malformed files.

 All entity lists include their terminal record, exactly as they will be written. This is plain C++ so that the fuzz
 target can use it as well as the XCTest suites.
 */
struct SF2Builder {
  struct PresetHeader { std::string name; uint16_t preset; uint16_t bank; uint16_t bagIndex; };
  struct Bag { uint16_t generatorIndex; uint16_t modulatorIndex; };
  struct Gen { uint16_t oper; uint16_t amount; };
  struct Mod { uint16_t source; uint16_t destination; int16_t amount; uint16_t amountSource; uint16_t transform; };
  struct Inst { std::string name; uint16_t bagIndex; };
  struct SampleHeader {
    std::string name;
    uint32_t start;
    uint32_t end;
    uint32_t startLoop;
    uint32_t endLoop;
    uint32_t sampleRate;
    uint8_t originalKey;
    int8_t correction;
    uint16_t link;
    uint16_t type;
  };

  // Generator opers used by `minimal()` (SF2.01 8.1.2)
  static constexpr uint16_t genInstrument = 41;
  static constexpr uint16_t genSampleID = 53;
  static constexpr uint16_t genSampleModes = 54;

  /// Number of samples in the sine wave of `minimal()`, not counting the 46 zero samples that follow it (SF2.01 7.10).
  static constexpr uint32_t sineSampleCount = 2'000;

  uint16_t versionMajor{2};
  uint16_t versionMinor{1};
  uint32_t ifilSize{4};
  std::string name{"SF2Builder"};
  std::vector<int16_t> samples;
  std::vector<PresetHeader> phdr;
  std::vector<Bag> pbag;
  std::vector<Mod> pmod;
  std::vector<Gen> pgen;
  std::vector<Inst> inst;
  std::vector<Bag> ibag;
  std::vector<Mod> imod;
  std::vector<Gen> igen;
  std::vector<SampleHeader> shdr;

  /// Four-character chunk tags (e.g. "phdr") to leave out of the file
  std::set<std::string> omittedChunks;

  /// Extra bytes to append to the data of a chunk, to make its size wrong
  std::map<std::string, std::vector<uint8_t>> extraChunkBytes;

  /// If set, the size to write in the `pdta` LIST header instead of the real one
  int64_t pdtaListSizeOverride{-1};

  /// Write pdta before sdta to construct an invalid top-level LIST order
  bool pdtaBeforeSdta{false};

  /**
   @returns builder for a valid file: preset "Sine" (bank 0, program 0) -> instrument "Sine" -> sample "Sine", a 441 Hz
   sine at 44.1 kHz with root key 69, looped over whole periods from sample 100 to 1900 (sampleModes = 1).
   */
  static SF2Builder minimal() {
    SF2Builder b;
    for (uint32_t index = 0; index < sineSampleCount; ++index) {
      b.samples.push_back(int16_t(std::lround(16'000.0 * std::sin(2.0 * M_PI * double(index) / 100.0))));
    }
    b.samples.insert(b.samples.end(), 46, 0);
    b.shdr = {{"Sine", 0, sineSampleCount, 100, 1'900, 44'100, 69, 0, 0, 1}, {"EOS", 0, 0, 0, 0, 0, 0, 0, 0, 0}};
    b.igen = {{genSampleModes, 1}, {genSampleID, 0}, {0, 0}};
    b.imod = {{0, 0, 0, 0, 0}};
    b.ibag = {{0, 0}, {2, 0}};
    b.inst = {{"Sine", 0}, {"EOI", 1}};
    b.pgen = {{genInstrument, 0}, {0, 0}};
    b.pmod = {{0, 0, 0, 0, 0}};
    b.pbag = {{0, 0}, {1, 0}};
    b.phdr = {{"Sine", 0, 0, 0}, {"EOP", 0, 0, 1}};
    return b;
  }

  /// @returns the file contents
  std::vector<uint8_t> build() const {
    Bytes info;
    {
      Bytes ifil;
      ifil.u16(versionMajor).u16(versionMinor);
      ifil.data.resize(ifilSize, 0);
      info.chunk("ifil", ifil, *this);
      Bytes inam;
      inam.text(name, name.size() + 1);
      info.chunk("INAM", inam, *this);
    }
    Bytes sdta;
    {
      Bytes smpl;
      for (auto sample : samples) smpl.u16(uint16_t(sample));
      sdta.chunk("smpl", smpl, *this);
    }
    Bytes pdta;
    {
      Bytes c;
      for (const auto& e : phdr) c.text(e.name, 20).u16(e.preset).u16(e.bank).u16(e.bagIndex).u32(0).u32(0).u32(0);
      pdta.chunk("phdr", c, *this);
      pdta.chunk("pbag", bags(pbag), *this);
      pdta.chunk("pmod", mods(pmod), *this);
      pdta.chunk("pgen", gens(pgen), *this);
      c = Bytes();
      for (const auto& e : inst) c.text(e.name, 20).u16(e.bagIndex);
      pdta.chunk("inst", c, *this);
      pdta.chunk("ibag", bags(ibag), *this);
      pdta.chunk("imod", mods(imod), *this);
      pdta.chunk("igen", gens(igen), *this);
      c = Bytes();
      for (const auto& e : shdr) {
        c.text(e.name, 20).u32(e.start).u32(e.end).u32(e.startLoop).u32(e.endLoop).u32(e.sampleRate)
          .u8(e.originalKey).u8(uint8_t(e.correction)).u16(e.link).u16(e.type);
      }
      pdta.chunk("shdr", c, *this);
    }

    Bytes body;
    body.tag("sfbk");
    body.list("INFO", info);
    if (pdtaBeforeSdta) {
      body.list("pdta", pdta, pdtaListSizeOverride);
      body.list("sdta", sdta);
    } else {
      body.list("sdta", sdta);
      body.list("pdta", pdta, pdtaListSizeOverride);
    }
    Bytes riff;
    riff.tag("RIFF").u32(uint32_t(body.data.size())).append(body);
    return riff.data;
  }

  /// Write the file contents to `path`. @returns true on success
  bool writeTo(const std::string& path) const {
    auto bytes = build();
    std::ofstream os(path, std::ios::binary | std::ios::trunc);
    os.write(reinterpret_cast<const char*>(bytes.data()), std::streamsize(bytes.size()));
    return bool(os);
  }

private:
  struct Bytes {
    std::vector<uint8_t> data;
    Bytes& u8(uint8_t v) { data.push_back(v); return *this; }
    Bytes& u16(uint16_t v) { return u8(uint8_t(v)).u8(uint8_t(v >> 8)); }
    Bytes& u32(uint32_t v) { return u16(uint16_t(v)).u16(uint16_t(v >> 16)); }
    Bytes& tag(const char* t) { for (int i = 0; i < 4; ++i) u8(uint8_t(t[i])); return *this; }
    /// Write exactly `size` bytes of `s`, zero-padded. A string of `size` characters is written without a NUL.
    Bytes& text(const std::string& s, size_t size) {
      for (size_t i = 0; i < size; ++i) u8(i < s.size() ? uint8_t(s[i]) : 0);
      return *this;
    }
    Bytes& append(const Bytes& other) { data.insert(data.end(), other.data.begin(), other.data.end()); return *this; }

    void chunk(const std::string& tag, Bytes contents, const SF2Builder& builder) {
      if (builder.omittedChunks.count(tag)) return;
      if (auto found = builder.extraChunkBytes.find(tag); found != builder.extraChunkBytes.end()) {
        contents.data.insert(contents.data.end(), found->second.begin(), found->second.end());
      }
      this->tag(tag.c_str()).u32(uint32_t(contents.data.size())).append(contents);
      if (contents.data.size() & 1) u8(0);
    }

    void list(const char* kind, const Bytes& contents, int64_t sizeOverride = -1) {
      tag("LIST").u32(sizeOverride >= 0 ? uint32_t(sizeOverride) : uint32_t(contents.data.size() + 4)).tag(kind)
        .append(contents);
    }
  };

  static Bytes bags(const std::vector<Bag>& v) {
    Bytes c; for (const auto& e : v) c.u16(e.generatorIndex).u16(e.modulatorIndex); return c;
  }
  static Bytes gens(const std::vector<Gen>& v) {
    Bytes c; for (const auto& e : v) c.u16(e.oper).u16(e.amount); return c;
  }
  static Bytes mods(const std::vector<Mod>& v) {
    Bytes c;
    for (const auto& e : v) c.u16(e.source).u16(e.destination).u16(uint16_t(e.amount)).u16(e.amountSource).u16(e.transform);
    return c;
  }
};
