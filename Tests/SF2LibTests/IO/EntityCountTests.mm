// Copyright © 2026 Brad Howes. All rights reserved.

#include <fcntl.h>
#include <unistd.h>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"
#include "SF2File/IO/File.hpp"

using namespace SF2;
using LoadResponse = SF2::IO::File::LoadResponse;
using Mod = SF2Builder::Mod;

static constexpr uint16_t cc16 = 0x0080 | 16;
static constexpr uint16_t cc17 = 0x0080 | 17;
static constexpr uint16_t attenuation = 48;

/**
 The minimal file, reshaped so that every count is different and non-zero where possible:

 - preset 0 has two zones: a global zone with 1 modulator and no generators, then a zone with 1 generator (instrument)
 - instrument 0 has one zone with 2 generators (sampleModes, sampleID) and 2 modulators

 The modulators have an amount of 0, so the file sounds like the minimal one.
 */
static SF2Builder makeBuilder()
{
  auto builder = SF2Builder::minimal();
  builder.pmod = {{cc16, attenuation, 0, 0, 0}, {0, 0, 0, 0, 0}};
  builder.pbag = {{0, 0}, {0, 1}, {1, 1}};
  builder.phdr[1].bagIndex = 2;
  builder.imod = {{cc16, attenuation, 0, 0, 0}, {cc17, attenuation, 0, 0, 0}, {0, 0, 0, 0, 0}};
  builder.ibag = {{0, 0}, {2, 2}};
  return builder;
}

static std::string writeBuilder(const SF2Builder& builder)
{
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibEntityCounts.sf2";
  builder.writeTo(path);
  return path;
}

@interface EntityCountTests : XCTestCase
@end

@implementation EntityCountTests

- (void)testCountsInContainer {
  IO::File file{writeBuilder(makeBuilder())};
  XCTAssertEqual(file.load(), LoadResponse::ok);

  XCTAssertEqual(file.presets().size(), size_t(1));
  XCTAssertEqual(file.presets()[0].zoneCount(), size_t(2));
  XCTAssertEqual(file.presetZones()[0].generatorCount(), size_t(0));
  XCTAssertEqual(file.presetZones()[0].modulatorCount(), size_t(1));
  XCTAssertEqual(file.presetZones()[1].generatorCount(), size_t(1));
  XCTAssertEqual(file.presetZones()[1].modulatorCount(), size_t(0));

  XCTAssertEqual(file.instruments().size(), size_t(1));
  XCTAssertEqual(file.instruments()[0].zoneCount(), size_t(1));
  XCTAssertEqual(file.instrumentZones()[0].generatorCount(), size_t(2));
  XCTAssertEqual(file.instrumentZones()[0].modulatorCount(), size_t(2));
}

- (void)testTerminalRecordsHaveNoCounts {
  IO::File file{writeBuilder(makeBuilder())};
  XCTAssertEqual(file.load(), LoadResponse::ok);
  XCTAssertEqual(file.presets()[file.presets().size()].zoneCount(), size_t(0));
  XCTAssertEqual(file.instruments()[file.instruments().size()].zoneCount(), size_t(0));
  const auto& pbagTerminal = file.presetZones()[file.presetZones().size()];
  XCTAssertEqual(pbagTerminal.generatorCount(), size_t(0));
  XCTAssertEqual(pbagTerminal.modulatorCount(), size_t(0));
  const auto& ibagTerminal = file.instrumentZones()[file.instrumentZones().size()];
  XCTAssertEqual(ibagTerminal.generatorCount(), size_t(0));
  XCTAssertEqual(ibagTerminal.modulatorCount(), size_t(0));
}

- (void)testCopiesOutsideTheContainerKeepTheirCounts {
  // §7: counts used to be `(this + 1)->firstIndex() - firstIndex()`, which is only valid inside the `ChunkItems`
  // vector. Each copy here is followed in memory by an identical copy, so the old code gave 0 for every count.
  IO::File file{writeBuilder(makeBuilder())};
  XCTAssertEqual(file.load(), LoadResponse::ok);

  std::array<Entity::Preset, 2> presets{file.presets()[0], file.presets()[0]};
  XCTAssertEqual(presets[0].zoneCount(), size_t(2));

  std::array<Entity::Bag, 2> pbags{file.presetZones()[0], file.presetZones()[0]};
  XCTAssertEqual(pbags[0].generatorCount(), size_t(0));
  XCTAssertEqual(pbags[0].modulatorCount(), size_t(1));

  std::array<Entity::Instrument, 2> instruments{file.instruments()[0], file.instruments()[0]};
  XCTAssertEqual(instruments[0].zoneCount(), size_t(1));

  std::array<Entity::Bag, 2> ibags{file.instrumentZones()[0], file.instrumentZones()[0]};
  XCTAssertEqual(ibags[0].generatorCount(), size_t(2));
  XCTAssertEqual(ibags[0].modulatorCount(), size_t(2));

  // A lone copy as well.
  Entity::Bag lone{file.instrumentZones()[0]};
  XCTAssertEqual(lone.generatorCount(), size_t(2));
}

- (void)testRecordsAreStillParsedAtTheirFileSize {
  // `Bag` and `Instrument` now hold counts after the file record, so they must read exactly `entity_size` bytes. If they
  // read `sizeof` bytes instead, the later records and names would be misread.
  IO::File file{writeBuilder(makeBuilder())};
  XCTAssertEqual(file.load(), LoadResponse::ok);
  XCTAssertEqual(std::string("Sine"), file.instruments()[0].name());
  XCTAssertEqual(std::string("EOI"), file.instruments()[1].name());
  XCTAssertEqual(file.instrumentZones()[1].firstGeneratorIndex(), size_t(2));
  XCTAssertEqual(file.instrumentZones()[1].firstModulatorIndex(), size_t(2));
  XCTAssertEqual(file.presetZones()[2].firstGeneratorIndex(), size_t(1));
  XCTAssertEqual(file.presetZones()[2].firstModulatorIndex(), size_t(1));
}

- (void)testMultiZonePresetRendersThroughEngine {
  // End to end: `Render::Preset` / `Render::Instrument` build their zones from these counts. The global preset zone
  // and the 2-modulator instrument zone must still produce the same sound as the minimal file (all amounts are 0).
  auto render = [](const SF2Builder& builder) {
    auto harness{TestEngineHarness{48000.0}};
    XCTAssertEqual(harness.load(writeBuilder(builder), 0), LoadResponse::ok);
    auto mixer{harness.createMixer(0.1)};
    harness.sendNoteOn(69, 127);
    XCTAssertEqual(harness.engine().activeVoiceCount(), size_t(1));
    harness.renderToEnd(mixer);
    const AUValue* data = harness.dryBuffer().floatChannelData[0];
    return std::vector<AUValue>(data, data + harness.bufferFrameCount());
  };
  auto expected = render(SF2Builder::minimal());
  auto samples = render(makeBuilder());
  XCTAssertGreaterThan(*std::max_element(samples.begin(), samples.end()), 0.1);
  XCTAssertTrue(samples == expected);
}

@end
