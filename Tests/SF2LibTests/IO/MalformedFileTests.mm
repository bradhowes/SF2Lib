// Copyright © 2026 Brad Howes. All rights reserved.

#include <fcntl.h>
#include <unistd.h>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

#include "SF2File/IO/File.hpp"

using namespace SF2;
using LoadResponse = SF2::IO::File::LoadResponse;

/// @returns path in the temporary directory for a test file
static std::string tempPath(const std::string& name)
{
  return std::string(NSTemporaryDirectory().UTF8String) + "SF2LibMalformed-" + name + ".sf2";
}

/// Write `bytes` to a temporary file and load it with `File::load(fd)`.
static LoadResponse loadBytes(const std::vector<uint8_t>& bytes, IO::File* file = nullptr)
{
  auto path = tempPath("bytes");
  {
    std::ofstream os(path, std::ios::binary | std::ios::trunc);
    os.write(reinterpret_cast<const char*>(bytes.data()), std::streamsize(bytes.size()));
  }
  int fd = ::open(path.c_str(), O_RDONLY);
  IO::File local;
  auto response = (file ? *file : local).load(fd);
  ::close(fd);
  return response;
}

static LoadResponse load(const SF2Builder& builder, IO::File* file = nullptr) { return loadBytes(builder.build(), file); }

/**
 Load the builder's file into an Engine through `loadFileAndPreset` and play key 69 for 0.1 s.

 @param response set to the engine's load response
 @returns the left channel of the dry bus
 */
static std::vector<AUValue> renderNote(const SF2Builder& builder, LoadResponse& response, size_t* voices = nullptr)
{
  auto path = tempPath("engine");
  builder.writeTo(path);
  auto harness{TestEngineHarness{48000.0}};
  response = harness.load(path, 0);
  auto mixer{harness.createMixer(0.1)};
  harness.sendNoteOn(69, 127);
  if (voices) *voices = harness.engine().activeVoiceCount();
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + harness.bufferFrameCount());
}

static double peak(const std::vector<AUValue>& samples)
{
  double value = 0.0;
  for (auto sample : samples) value = std::max(value, std::abs(double(sample)));
  return value;
}

@interface MalformedFileTests : XCTestCase
@end

@implementation MalformedFileTests

- (void)testMinimalFileLoadsAndPlays {
  // Sanity check of the builder itself: the minimal file is valid and makes sound through the engine.
  auto builder = SF2Builder::minimal();
  IO::File file;
  XCTAssertEqual(load(builder, &file), LoadResponse::ok);
  XCTAssertEqual(file.presets().size(), size_t(1));
  XCTAssertEqual(std::string("Sine"), std::string(file.presets()[0].name()));
  XCTAssertEqual(file.sampleHeaders().size(), size_t(1));

  LoadResponse response;
  size_t voices = 0;
  auto samples = renderNote(builder, response, &voices);
  XCTAssertEqual(response, LoadResponse::ok);
  XCTAssertEqual(voices, size_t(1));
  XCTAssertGreaterThan(peak(samples), 0.01);
}

- (void)testEveryTruncationIsRejected {
  // Previously a truncated pdta sub-chunk threw inside a noexcept function, which terminated the host.
  auto bytes = SF2Builder::minimal().build();
  for (size_t length = 0; length < bytes.size(); length += 3) {
    std::vector<uint8_t> truncated(bytes.begin(), bytes.begin() + long(length));
    XCTAssertEqual(loadBytes(truncated), LoadResponse::invalidFormat, @"length %zu", length);
  }
}

- (void)testMissingRequiredChunksAreRejected {
  // A missing phdr used to make `ChunkItems::size()` underflow, and the preset index `resize(SIZE_MAX)` terminated.
  for (auto tag : {"phdr", "pbag", "inst", "ibag", "shdr"}) {
    auto builder = SF2Builder::minimal();
    builder.omittedChunks.insert(tag);
    XCTAssertEqual(load(builder), LoadResponse::invalidFormat, @"%s", tag);
  }
}

- (void)testOnlyTerminalPresetIsRejected {
  auto builder = SF2Builder::minimal();
  builder.phdr = {{"EOP", 0, 0, 0}};
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
}

- (void)testMissingModulatorListsAreAccepted {
  // No bag refers to a modulator, so files that leave out the (empty) modulator lists still load and play.
  auto builder = SF2Builder::minimal();
  builder.omittedChunks = {"pmod", "imod"};
  XCTAssertEqual(load(builder), LoadResponse::ok);
  LoadResponse response;
  XCTAssertGreaterThan(peak(renderNote(builder, response)), 0.01);
  XCTAssertEqual(response, LoadResponse::ok);
}

- (void)testChunkSizeNotMultipleOfEntitySizeIsRejected {
  // SF2.01 7.2-7.10: "If the ... chunk size is not a multiple of N bytes ... the file should be rejected".
  for (auto tag : {"phdr", "pbag", "pmod", "pgen", "inst", "ibag", "imod", "igen", "shdr"}) {
    auto builder = SF2Builder::minimal();
    builder.extraChunkBytes[tag] = {0, 0};
    XCTAssertEqual(load(builder), LoadResponse::invalidFormat, @"%s", tag);
  }
}

- (void)testMissingIfilIsRejected {
  // SF2.01 5.1: "If the ifil sub-chunk is missing, or its size is not four bytes, the file should be rejected".
  auto builder = SF2Builder::minimal();
  builder.omittedChunks.insert("ifil");
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
}

- (void)testROMSampleIsRejected {
  // SF2.01 5.4, 5.5, 7.10: there is no ROM sample memory, so an instrument that uses a ROM sample makes the file be
  // rejected. Previously it was played from `smpl` as if it were a RAM sample.
  auto builder = SF2Builder::minimal();
  builder.shdr[0].type = 0x8001; // romMonoSample
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);

  // A ROM header that no instrument uses does not matter.
  builder = SF2Builder::minimal();
  builder.shdr.insert(builder.shdr.end() - 1, {"ROM", 0, 100, 10, 90, 44'100, 60, 0, 0, 0x8001});
  XCTAssertEqual(load(builder), LoadResponse::ok);
}

- (void)testDuplicateBankProgramFirstWins {
  // SF2.01 7.2: if two presets have the same bank and program, the first one in PHDR is used. 40 presets alternating
  // between programs 0 and 1 is a pattern that libc++'s (unstable) `std::sort` reorders, so this catches a regression
  // from `std::stable_sort`.
  const size_t duplicates = 40;
  auto builder = SF2Builder::minimal();
  builder.phdr.clear();
  builder.pbag.clear();
  builder.pgen.clear();
  for (size_t index = 0; index < duplicates; ++index) {
    // Bank 0, program 0 or 1, each with its own zone that uses the same instrument.
    builder.phdr.push_back({"P" + std::to_string(index), uint16_t(index % 2), 0, uint16_t(index)});
    builder.pbag.push_back({uint16_t(index), 0});
    builder.pgen.push_back({SF2Builder::genInstrument, 0});
  }
  builder.phdr.push_back({"EOP", 0, 0, uint16_t(duplicates)});
  builder.pbag.push_back({uint16_t(duplicates), 0});
  builder.pgen.push_back({0, 0});

  IO::File file;
  XCTAssertEqual(load(builder, &file), LoadResponse::ok);
  // Program 0 presets first (P0, P2, ...), then program 1 (P1, P3, ...), each group in file order.
  const auto& order = file.presetIndicesOrderedByBankProgram();
  XCTAssertEqual(order.size(), duplicates);
  for (size_t index = 0; index < order.size(); ++index) {
    auto expected = index < duplicates / 2 ? index * 2 : (index - duplicates / 2) * 2 + 1;
    XCTAssertEqual(order[index], expected, @"position %zu", index);
  }

  // And through the Engine: selecting bank 0 / program 0 or 1 picks the first such preset in the file.
  auto path = tempPath("duplicates");
  builder.writeTo(path);
  auto harness{TestEngineHarness{48000.0}};
  XCTAssertEqual(harness.load(path, 5), LoadResponse::ok);
  harness.sendRaw(harness.engine().createUseBankProgramPayload(0, 0));
  harness.drainWorkQueue();
  XCTAssertEqual(std::string("P0"), harness.engine().activePresetName());
  harness.sendRaw(harness.engine().createUseBankProgramPayload(0, 1));
  harness.drainWorkQueue();
  XCTAssertEqual(std::string("P1"), harness.engine().activePresetName());
}

- (void)testBadIfilSizeIsRejected {
  auto builder = SF2Builder::minimal();
  builder.ifilSize = 2;
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
}

- (void)testListSizeBelowFourIsRejected {
  // The LIST size includes its 4-byte kind tag. A smaller value used to underflow to ~4 GB.
  auto builder = SF2Builder::minimal();
  builder.pdtaListSizeOverride = 2;
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
}

- (void)testInstrumentLinkOutOfRangeIsRejected {
  // SF2.01 7.5. Previously `Zone::Preset` took `&instruments[index]` without a check.
  auto builder = SF2Builder::minimal();
  builder.pgen[0].amount = 5;
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);

  LoadResponse response;
  size_t voices = 99;
  auto samples = renderNote(builder, response, &voices);
  XCTAssertEqual(response, LoadResponse::invalidFormat);
  XCTAssertEqual(voices, size_t(0));
  XCTAssertEqual(peak(samples), 0.0);
}

- (void)testSampleLinkOutOfRangeIsRejected {
  // SF2.01 7.9
  auto builder = SF2Builder::minimal();
  builder.igen[1].amount = 1;
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
}

- (void)testSampleOutsideSampleDataIsRejected {
  // The end is past the smpl chunk, so the samples would have been read from pdta or beyond the file.
  auto builder = SF2Builder::minimal();
  builder.shdr[0].end = 10'000;
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);

  builder = SF2Builder::minimal();
  builder.shdr[0].start = 1'500;
  builder.shdr[0].end = 1'000;
  XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
}

- (void)testBadZoneIndicesAreRejected {
  {
    // Terminal preset points past the last preset bag
    auto builder = SF2Builder::minimal();
    builder.phdr[1].bagIndex = 5;
    XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
  }
  {
    // Decreasing preset bag indices
    auto builder = SF2Builder::minimal();
    builder.phdr[0].bagIndex = 1;
    builder.phdr[1].bagIndex = 0;
    XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
  }
  {
    // Instrument bag generator index past the end of igen
    auto builder = SF2Builder::minimal();
    builder.ibag[1].generatorIndex = 10;
    XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
  }
  {
    // Instrument bag modulator index past the end of imod
    auto builder = SF2Builder::minimal();
    builder.ibag[1].modulatorIndex = 3;
    XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
  }
  {
    // Terminal instrument points past the last instrument bag
    auto builder = SF2Builder::minimal();
    builder.inst[1].bagIndex = 7;
    XCTAssertEqual(load(builder), LoadResponse::invalidFormat);
  }
}

- (void)testUnknownGeneratorsAreIgnored {
  // SF2.01 8.1: unknown generators are ignored. Previously gen 59+ read past `Definition::definitions_` and wrote past
  // `State::gens_`. The note must render exactly as it does without them.
  auto builder = SF2Builder::minimal();
  LoadResponse response;
  auto reference = renderNote(builder, response);
  XCTAssertEqual(response, LoadResponse::ok);

  builder.igen.insert(builder.igen.begin(), {{59, 1'000}, {60, 1'000}, {1'000, 1'000}, {0xFFFF, 1'000}});
  builder.ibag[1].generatorIndex += 4;
  builder.pgen.insert(builder.pgen.begin(), {{59, 1'000}, {0xFFFF, 1'000}});
  builder.pbag[1].generatorIndex += 2;
  IO::File file;
  XCTAssertEqual(load(builder, &file), LoadResponse::ok);
  // Dumping a file with unknown generators must not read past the definitions either.
  file.dump();

  auto withUnknown = renderNote(builder, response);
  XCTAssertEqual(response, LoadResponse::ok);
  XCTAssertGreaterThan(peak(reference), 0.01);
  XCTAssertTrue(reference == withUnknown);
}

- (void)testInvalidModulatorsAreIgnored {
  // SF2.01 8.2: a modulator whose destination is not a generator, or whose sources are not valid, is ignored.
  // Previously the destination was used directly as an index into `State::gens_`. They all use CC 16, which no default
  // modulator uses. Both renderings send it, so any effect from these modulators would show up as a difference.
  auto render = [](const SF2Builder& builder) {
    auto path = tempPath("mods");
    builder.writeTo(path);
    auto harness{TestEngineHarness{48000.0}};
    auto response = harness.load(path, 0);
    auto mixer{harness.createMixer(0.1)};
    harness.sendRaw(std::array<uint8_t, 3>{0xB0, 16, 127});
    harness.sendNoteOn(69, 127);
    harness.sendRaw(std::array<uint8_t, 3>{0xB0, 16, 64});
    harness.renderToEnd(mixer);
    const AUValue* data = harness.dryBuffer().floatChannelData[0];
    return std::make_pair(response, std::vector<AUValue>(data, data + harness.bufferFrameCount()));
  };

  auto builder = SF2Builder::minimal();
  auto [referenceResponse, reference] = render(builder);
  XCTAssertEqual(referenceResponse, LoadResponse::ok);

  const uint16_t cc16 = 0x0080 | 16;  // CC flag + CC 16, positive unipolar linear
  const uint16_t badCC = 0x0080 | 6;  // CC 6 (data entry) is not a valid source
  const uint16_t link = 127;          // 2.04 link source, not supported
  builder.imod = {
    {cc16, 1'000, 100, 0, 0},         // destination past the generators
    {cc16, 0x8000 | 2, 100, 0, 0},    // 2.04 link destination (bit 15)
    {cc16, 48, 960, badCC, 0},        // invalid amount source -> attenuation
    {link, 48, 960, 0, 0},            // unsupported source -> attenuation
    {0, 0, 0, 0, 0}};
  builder.ibag = {{0, 0}, {2, 4}};
  XCTAssertEqual(load(builder), LoadResponse::ok);

  auto [response, rendered] = render(builder);
  XCTAssertEqual(response, LoadResponse::ok);
  XCTAssertGreaterThan(peak(reference), 0.01);
  XCTAssertTrue(reference == rendered);

  // Guard against a vacuous test: a valid CC 16 -> attenuation modulator does change the rendering.
  builder.imod = {{cc16, 48, 960, 0, 0}, {0, 0, 0, 0, 0}};
  builder.ibag = {{0, 0}, {2, 1}};
  auto [validResponse, modulated] = render(builder);
  XCTAssertEqual(validResponse, LoadResponse::ok);
  XCTAssertFalse(reference == modulated);
}

- (void)testTwentyCharacterNameIsTerminated {
  // SF2 names are 20 bytes and should end with a NUL. One that fills all 20 used to be read past the end of the array.
  auto builder = SF2Builder::minimal();
  builder.phdr[0].name = "ABCDEFGHIJKLMNOPQRST";
  builder.inst[0].name = "abcdefghijklmnopqrst";
  builder.shdr[0].name = "01234567890123456789";
  IO::File file;
  XCTAssertEqual(load(builder, &file), LoadResponse::ok);
  XCTAssertEqual(std::string("ABCDEFGHIJKLMNOPQRS"), std::string(file.presets()[0].name()));
  XCTAssertEqual(std::string("abcdefghijklmnopqrs"), std::string(file.instruments()[0].name()));
  XCTAssertEqual(std::string("0123456789012345678"), std::string(file.sampleHeaders()[0].sampleName()));
}

- (void)testHighBitCharactersInNamesAreSanitized {
  // Latin-1 bytes are common in older files. std::isprint on a negative char is undefined behaviour.
  auto builder = SF2Builder::minimal();
  builder.phdr[0].name = "Caf\xE9 Piano";
  IO::File file;
  XCTAssertEqual(load(builder, &file), LoadResponse::ok);
  XCTAssertEqual(std::string("Caf_ Piano"), std::string(file.presets()[0].name()));
}

- (void)testPresetWithoutSamplesIsSilent {
  // A preset whose instrument has no zones has no samples to load. `loadSamples` used to compute `maxEnd - minStart`
  // with maxEnd < minStart and try to allocate ~SIZE_MAX samples.
  auto builder = SF2Builder::minimal();
  builder.inst = {{"Empty", 0}, {"EOI", 0}};
  builder.ibag = {{0, 0}};
  builder.igen = {{0, 0}};
  builder.imod = {{0, 0, 0, 0, 0}};
  builder.shdr = {{"EOS", 0, 0, 0, 0, 0, 0, 0, 0, 0}};
  XCTAssertEqual(load(builder), LoadResponse::ok);

  LoadResponse response;
  size_t voices = 99;
  auto samples = renderNote(builder, response, &voices);
  XCTAssertEqual(response, LoadResponse::ok);
  XCTAssertEqual(voices, size_t(0));
  XCTAssertEqual(peak(samples), 0.0);
}

- (void)testZeroSampleRateUsesPracticalMinimum {
  // Found by the fuzzer. SF2.01 7.10: a sample rate of zero is illegal and "the nearest practical value should be used".
  // `Pitch` used to take log2(0) and convert -inf to an int.
  auto builder = SF2Builder::minimal();
  builder.shdr[0].sampleRate = 0;
  LoadResponse response;
  auto zero = renderNote(builder, response);
  XCTAssertEqual(response, LoadResponse::ok);
  builder.shdr[0].sampleRate = 400;
  auto minimum = renderNote(builder, response);
  XCTAssertTrue(std::all_of(zero.begin(), zero.end(), [](AUValue v) { return std::isfinite(v); }));
  XCTAssertGreaterThan(peak(zero), 0.01);
  XCTAssertTrue(zero == minimum);
}

- (void)testInvalidLoopIsNotUsed {
  // Found by the fuzzer. With the loop end (0) before the loop start (50), the sample has no usable loop, but the voice
  // still asked to loop because sampleModes is 1. Cubic interpolation at the loop start then read the sample *before*
  // the start of the buffer. The note must render exactly as the same sample with looping turned off.
  auto builder = SF2Builder::minimal();
  builder.shdr[0].startLoop = 50;
  builder.shdr[0].endLoop = 0;
  LoadResponse response;
  auto looped = renderNote(builder, response);
  XCTAssertEqual(response, LoadResponse::ok);
  builder.igen[0].amount = 0; // sampleModes = 0, no loop
  auto unlooped = renderNote(builder, response);
  XCTAssertGreaterThan(peak(unlooped), 0.01);
  XCTAssertTrue(looped == unlooped);
}

- (void)testRandomByteCorruptionNeverCrashes {
  // A small, deterministic stand-in for the libFuzzer target in Fuzz/: flip random bytes in the minimal file, then load
  // it and, if it loads, play a note. Any crash, sanitizer report or exception escaping a noexcept function fails the
  // run. The outcome of each load is not checked; some corruptions are harmless.
  auto original = SF2Builder::minimal().build();
  uint32_t seed = 0x5F2;
  auto next = [&seed]() { seed = seed * 1'664'525u + 1'013'904'223u; return seed; };
  size_t loaded = 0;
  for (int iteration = 0; iteration < 300; ++iteration) {
    auto bytes = original;
    auto flips = 1 + next() % 8;
    for (uint32_t flip = 0; flip < flips; ++flip) {
      bytes[next() % bytes.size()] = uint8_t(next());
    }
    auto path = tempPath("random");
    {
      std::ofstream os(path, std::ios::binary | std::ios::trunc);
      os.write(reinterpret_cast<const char*>(bytes.data()), std::streamsize(bytes.size()));
    }
    auto harness{TestEngineHarness{48000.0}};
    if (harness.load(path, 0) == LoadResponse::ok) {
      ++loaded;
      auto mixer{harness.createMixer(0.02)};
      harness.sendNoteOn(69, 127);
      harness.renderToEnd(mixer);
    }
  }
  // Most single-byte changes land in sample data or names, so plenty of files still load and get rendered.
  XCTAssertGreaterThan(loaded, size_t(50));
}

@end
