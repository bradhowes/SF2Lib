// Copyright © 2026 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"
#include "SF2File/IO/File.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"

using namespace SF2;
using LoadResponse = SF2::IO::File::LoadResponse;

// §6 item 7: `Preset::loadSamples` used to load everything between the lowest sample start and the highest sample end
// that a preset uses. These files put a large sample that the preset does not use between the two that it does.

static constexpr uint16_t genKeyRange = 43;
static constexpr uint32_t sineCount = SF2Builder::sineSampleCount;
static constexpr uint32_t padding = 46;
static constexpr uint32_t fillerCount = 100'000;

/// Append a looping sine sample with the given period and its 46 padding samples, and its header.
static void addSine(SF2Builder& builder, const std::string& name, double period)
{
  auto start = uint32_t(builder.samples.size());
  for (uint32_t index = 0; index < sineCount; ++index) {
    builder.samples.push_back(int16_t(std::lround(16'000.0 * std::sin(2.0 * M_PI * double(index) / period))));
  }
  builder.samples.insert(builder.samples.end(), padding, 0);
  builder.shdr.insert(builder.shdr.end() - 1, {name, start, start + sineCount, start + 100, start + 1'900, 44'100, 69, 0,
    0, 1});
}

/// Append a sample of `count` non-zero values (that no zone uses) and its padding, and its header.
static void addFiller(SF2Builder& builder, uint32_t count)
{
  auto start = uint32_t(builder.samples.size());
  builder.samples.insert(builder.samples.end(), count, 1'000);
  builder.samples.insert(builder.samples.end(), padding, 0);
  builder.shdr.insert(builder.shdr.end() - 1, {"Filler", start, start + count, start + 8, start + count - 8, 44'100, 60,
    0, 0, 1});
}

/**
 An instrument with two zones: keys 0-63 play sample `low`, keys 64-127 play sample `high`.

 @param withFiller if true, a large unused sample sits between the two sines in the `smpl` chunk
 */
static SF2Builder makeBuilder(bool withFiller)
{
  auto builder = SF2Builder::minimal();
  builder.samples.clear();
  builder.shdr = {{"EOS", 0, 0, 0, 0, 0, 0, 0, 0, 0}};
  addSine(builder, "Low", 100.0);
  if (withFiller) addFiller(builder, fillerCount);
  addSine(builder, "High", 37.0);
  uint16_t high = withFiller ? 2 : 1;
  builder.igen = {
    {genKeyRange, uint16_t(0 | (63 << 8))}, {SF2Builder::genSampleModes, 1}, {SF2Builder::genSampleID, 0},
    {genKeyRange, uint16_t(64 | (127 << 8))}, {SF2Builder::genSampleModes, 1}, {SF2Builder::genSampleID, high},
    {0, 0}};
  builder.ibag = {{0, 0}, {3, 0}, {6, 0}};
  builder.inst[1].bagIndex = 2;  // the terminal record: the instrument has two zones
  return builder;
}

static std::string writeBuilder(const SF2Builder& builder, const std::string& name)
{
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibSampleLoading-" + name + ".sf2";
  builder.writeTo(path);
  return path;
}

/// Load preset 0 of the file and its samples. @returns the number of samples held for it.
static size_t loadedSampleCount(const std::string& path)
{
  IO::File file{path};
  if (file.load() != LoadResponse::ok) return 0;
  Render::PresetCollection presets;
  presets.build(file);
  if (!presets[0].loadSamples(file)) return 0;
  return presets[0].loadedSampleCount();
}

/// Play `key` for 0.1 s through the engine and return the left channel.
static std::vector<AUValue> render(const std::string& path, uint8_t key)
{
  auto harness{TestEngineHarness{48000.0}};
  if (harness.load(path, 0) != LoadResponse::ok) return {};
  auto mixer{harness.createMixer(0.1)};
  harness.sendNoteOn(key, 127);
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + harness.bufferFrameCount());
}

@interface PresetSampleLoadingTests : XCTestCase
@end

@implementation PresetSampleLoadingTests

- (void)testOnlyUsedSamplesAreLoaded {
  // The two sines and their padding, not the 100,000-sample filler between them.
  auto path = writeBuilder(makeBuilder(true), "spread");
  XCTAssertEqual(loadedSampleCount(path), size_t(2 * (sineCount + padding)));
}

- (void)testAdjacentSamplesStillLoadAsOneRun {
  // Without the filler the two sines are back to back (each followed by its padding), which merges into one run of
  // exactly the same size.
  auto path = writeBuilder(makeBuilder(false), "adjacent");
  XCTAssertEqual(loadedSampleCount(path), size_t(2 * (sineCount + padding)));
}

- (void)testSharedSampleIsLoadedOnce {
  // Both zones play the same sample.
  auto builder = makeBuilder(true);
  builder.igen[5] = {SF2Builder::genSampleID, 0};
  XCTAssertEqual(loadedSampleCount(writeBuilder(builder, "shared")), size_t(sineCount + padding));
}

- (void)testOverlappingHeadersAreLoadedOnce {
  // A second header covering only the first half of the low sine (with different loop points) overlaps the first.
  auto builder = makeBuilder(true);
  builder.shdr.insert(builder.shdr.end() - 1, {"LowHalf", 0, sineCount / 2, 50, 900, 44'100, 69, 0, 0, 1});
  builder.igen[5] = {SF2Builder::genSampleID, 3};
  XCTAssertEqual(loadedSampleCount(writeBuilder(builder, "overlap")), size_t(sineCount + padding));
}

- (void)testSpreadSamplesRenderLikeAdjacentOnes {
  // End to end: with the filler removed from the loaded data, each zone's span must still point at the right samples.
  auto spread = writeBuilder(makeBuilder(true), "spread-render");
  auto adjacent = writeBuilder(makeBuilder(false), "adjacent-render");
  for (uint8_t key : {60, 72}) {
    auto expected = render(adjacent, key);
    XCTAssertFalse(expected.empty());
    XCTAssertGreaterThan(*std::max_element(expected.begin(), expected.end()), 0.1, @"key %d", key);
    XCTAssertTrue(render(spread, key) == expected, @"key %d", key);
  }
  // Guard against a vacuous test: the two zones really do play different samples.
  XCTAssertFalse(render(adjacent, 60) == render(adjacent, 72));
}

- (void)testPresetWithoutSamplesLoadsNothing {
  auto builder = makeBuilder(true);
  builder.igen = {{SF2Builder::genSampleModes, 1}, {0, 0}};
  builder.ibag = {{0, 0}, {1, 0}};
  builder.inst[1].bagIndex = 1;
  auto path = writeBuilder(builder, "none");
  IO::File file{path};
  XCTAssertEqual(file.load(), LoadResponse::ok);
  Render::PresetCollection presets;
  presets.build(file);
  XCTAssertTrue(presets[0].loadSamples(file));
  XCTAssertEqual(presets[0].loadedSampleCount(), size_t(0));
}

@end
