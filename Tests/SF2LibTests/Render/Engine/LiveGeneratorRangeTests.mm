// Copyright © 2026 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"
#include "SF2Lib/Render/Engine/LiveGeneratorParameters.hpp"
#include "SF2Lib/Render/LowPassFilter.hpp"

using namespace SF2;
using Index = SF2::Entity::Generator::Index;
using LiveGeneratorParameters = SF2::Render::Engine::LiveGeneratorParameters;
using LowPassFilter = SF2::Render::LowPassFilter;
using SF2::Entity::Generator::IndexIterator;

// Live generator values (AUParameterTree) used to be clamped to the spec ranges, so a live envelope delay or attack
// could not be -32768 (no time; -12000 is 1 ms) and a live filter cutoff could not reach the filter bypass.

static constexpr AUAudioFrameCount renderFrames = 480;
static constexpr uint16_t genInitialFilterCutoff = 8;
static constexpr uint16_t genDelayVolEnv = 33;
static constexpr uint16_t genAttackVolEnv = 34;

/**
 Render one note from `builder`, after `configure` has set any live values.

 @returns the left channel
 */
static std::vector<AUValue> render(const SF2Builder& builder, std::function<void(TestEngineHarness&)> configure)
{
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibLiveGeneratorRange.sf2";
  builder.writeTo(path);
  auto harness{TestEngineHarness{48000.0}};
  harness.load(path, 0);
  if (configure) configure(harness);
  auto mixer{harness.createMixer(double(renderFrames) / 48000.0)};
  harness.sendNoteOn(69, 127);
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + renderFrames);
}

@interface LiveGeneratorRangeTests : XCTestCase
@end

@implementation LiveGeneratorRangeTests

- (void)testLiveValuesMatchTheSameValuesInTheFile {
  // No delay, an instant attack and a bypassed filter set live must sound exactly like the same generators in the
  // instrument zone (where they were never clamped).
  auto inFile = SF2Builder::minimal();
  inFile.igen = {{genInitialFilterCutoff, uint16_t(LowPassFilter::bypassFrequency)},
    {genDelayVolEnv, uint16_t(int16_t(-32'768))}, {genAttackVolEnv, uint16_t(int16_t(-32'768))},
    {SF2Builder::genSampleModes, 1}, {SF2Builder::genSampleID, 0}, {0, 0}};
  inFile.ibag = {{0, 0}, {5, 0}};
  auto expected = render(inFile, nullptr);

  auto live = render(SF2Builder::minimal(), [](TestEngineHarness& harness) {
    harness.setParameter(Index::initialFilterCutoff, 20'000);  // clamped to the bypass frequency
    harness.setParameter(Index::delayVolumeEnvelope, -32'768);
    harness.setParameter(Index::attackVolumeEnvelope, -32'768);
  });
  XCTAssertTrue(live == expected);

  // Guard against a vacuous test: with the defaults (1 ms delay and attack, filter on) the start is silent.
  auto defaults = render(SF2Builder::minimal(), nullptr);
  XCTAssertEqual(defaults[1], 0.0f);
  XCTAssertNotEqual(live[1], 0.0f);
  XCTAssertFalse(live == defaults);
}

- (void)testLiveValueRanges {
  LiveGeneratorParameters parameters;
  auto check = [&](Index index, AUValue value, AUValue expected) {
    parameters.setLiveValue(index, value);
    XCTAssertEqual(parameters.getLiveValue(index), expected, @"generator %d value %f", int(index), value);
  };

  // Envelope delay and attack: down to -32768, upper bound as in the spec.
  for (auto index : {Index::delayVolumeEnvelope, Index::attackVolumeEnvelope, Index::delayModulatorEnvelope,
    Index::attackModulatorEnvelope}) {
    check(index, -40'000, -32'768);
    check(index, -32'768, -32'768);
    check(index, -20'000, -20'000);
    auto max = Entity::Generator::Definition::definition(index).valueRange().max;
    check(index, AUValue(max + 1'000), AUValue(max));
  }

  // Filter cutoff: up to the bypass frequency, lower bound as in the spec.
  check(Index::initialFilterCutoff, 20'000, LowPassFilter::bypassFrequency);
  check(Index::initialFilterCutoff, 13'505, 13'505);
  check(Index::initialFilterCutoff, 0, 1'500);

  // Everything else keeps the spec range, e.g. pan and the LFO delays.
  check(Index::pan, 900, 500);
  check(Index::delayModulatorLFO, -32'768, -12'000);
  check(Index::delayVibratoLFO, -32'768, -12'000);
}

- (void)testParameterTreeUsesTheLiveRanges {
  auto harness{TestEngineHarness{48000.0}};
  auto tree = harness.engine().parameterTree();
  for (auto index : IndexIterator()) {
    auto definition = Entity::Generator::Definition::definition(index);
    if (definition.valueKind() == Entity::Generator::Definition::ValueKind::UNUSED) continue;
    auto parameter = [tree parameterWithAddress:AUParameterAddress(DSPHeaders::valueOf(index))];
    XCTAssertNotNil(parameter);
    auto range = LiveGeneratorParameters::liveValueRange(index);
    XCTAssertEqual(parameter.minValue, AUValue(range.min), @"generator %d", int(index));
    XCTAssertEqual(parameter.maxValue, AUValue(range.max), @"generator %d", int(index));
  }
  XCTAssertEqual([tree parameterWithAddress:DSPHeaders::valueOf(Index::attackVolumeEnvelope)].minValue, -32'768.0f);
  XCTAssertEqual([tree parameterWithAddress:DSPHeaders::valueOf(Index::initialFilterCutoff)].maxValue,
                 AUValue(LowPassFilter::bypassFrequency));
}

@end
