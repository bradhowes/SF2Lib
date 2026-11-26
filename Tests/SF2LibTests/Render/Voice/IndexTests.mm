// Copyright © 2026 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"

#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"
#include "SF2Lib/Render/Voice/Sample/Index.hpp"
#include "SF2Lib/Render/Zone/NormalizedSampleSpan.hpp"

using namespace SF2;
using namespace SF2::Entity;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Voice::Sample;
using GenIndex = SF2::Entity::Generator::Index;

// Same headers as BoundsTests: samples 11..139, loop 54..101. Relative to the start that is 0..128, loop 43..90.
static SampleHeader sampleHeaderNoLoop{11, 139, 0, 0, 48'000, 0, 0};
static SampleHeader sampleHeaderLooped{11, 139, 54, 101, 48'000, 0, 0};

@interface IndexTests : SamplePlayingTestCase
@end

@implementation IndexTests

- (Index)startedIndex:(const SampleHeader&)header state:(const State::State&)state {
  Index index;
  index.configure(Bounds::make(header, state));
  index.start();
  return index;
}

- (void)testStartsAtZeroWithoutOffset {
  auto state = State::State(48'000.0);
  auto index = [self startedIndex:sampleHeaderNoLoop state:state];
  XCTAssertEqual(index.whole(), size_t(0));
  XCTAssertEqual(index.partial(), 0_F);
}

- (void)testStartsAtStartAddressOffset {
  // SF2.01 8.1.2 #0 startAddrsOffset
  auto state = State::State(48'000.0);
  self.sst.setValue(state, GenIndex::startAddressOffset, 10);
  auto index = [self startedIndex:sampleHeaderNoLoop state:state];
  XCTAssertEqual(index.whole(), size_t(10));
  XCTAssertFalse(index.finished());
}

- (void)testStartsAtStartAddressCoarseOffset {
  // SF2.01 8.1.2 #4 startAddrsCoarseOffset: 32768-sample units added to startAddrsOffset. Use a header long enough to
  // hold a coarse step.
  SampleHeader longHeader{0, 100'000, 0, 0, 48'000, 0, 0};
  auto state = State::State(48'000.0);
  self.sst.setValue(state, GenIndex::startAddressCoarseOffset, 2);
  self.sst.setValue(state, GenIndex::startAddressOffset, 5);
  auto index = [self startedIndex:longHeader state:state];
  XCTAssertEqual(index.whole(), size_t(2 * 32'768 + 5));
}

- (void)testStartOffsetPastEndIsFinished {
  auto state = State::State(48'000.0);
  self.sst.setValue(state, GenIndex::startAddressOffset, 1'000);
  auto index = [self startedIndex:sampleHeaderNoLoop state:state];
  XCTAssertTrue(index.finished());
}

- (void)testRestartReturnsToStartOffset {
  auto state = State::State(48'000.0);
  self.sst.setValue(state, GenIndex::startAddressOffset, 10);
  auto index = [self startedIndex:sampleHeaderNoLoop state:state];
  for (int count = 0; count < 20; ++count) index.increment(1_F, false);
  XCTAssertEqual(index.whole(), size_t(30));
  index.start();
  XCTAssertEqual(index.whole(), size_t(10));
}

- (void)testStartInsideLoopStillLoops {
  // Starting partway into the loop must not disable it. The index plays to the loop end and wraps to the loop start.
  auto state = State::State(48'000.0);
  self.sst.setValue(state, GenIndex::startAddressOffset, 60);
  auto bounds = Bounds::make(sampleHeaderLooped, state);
  XCTAssertTrue(bounds.hasLoop());
  auto index = [self startedIndex:sampleHeaderLooped state:state];
  XCTAssertEqual(index.whole(), size_t(60));
  for (int count = 0; count < 30; ++count) index.increment(1_F, true);
  // 60 + 30 reaches the loop end (90), which wraps to the loop start (43).
  XCTAssertEqual(index.whole(), size_t(43));
  XCTAssertTrue(index.looped());
}

- (void)testStartPastLoopEndDoesNotJumpBack {
  // Starting after the loop end means the loop can never be reached. Playback runs on to the end of the sample.
  auto state = State::State(48'000.0);
  self.sst.setValue(state, GenIndex::startAddressOffset, 100);
  XCTAssertFalse(Bounds::make(sampleHeaderLooped, state).hasLoop());
  auto index = [self startedIndex:sampleHeaderLooped state:state];
  XCTAssertEqual(index.whole(), size_t(100));
  index.increment(1_F, true);
  XCTAssertEqual(index.whole(), size_t(101));
  XCTAssertFalse(index.looped());
  for (int count = 0; count < 27; ++count) index.increment(1_F, true);
  XCTAssertTrue(index.finished());
}

- (void)testLargeIncrementStaysInsideShortLoop {
  // §3.3: `increment` used to subtract the loop size once. With an increment larger than the loop (a short loop played
  // at a high pitch) the index stayed past the loop end and drifted forward without ever stopping.
  auto state = State::State(48'000.0);
  auto index = [self startedIndex:sampleHeaderLooped state:state]; // loop 43..90 (47 samples)
  size_t expected = 0;
  for (int count = 0; count < 200; ++count) {
    index.increment(100_F, true);
    expected += 100;
    if (expected >= 90) expected = 43 + (expected - 90) % 47;
    XCTAssertEqual(index.whole(), expected, @"step %d", count);
    XCTAssertGreaterThanOrEqual(index.whole(), size_t(43));
    XCTAssertLessThan(index.whole(), size_t(90));
    XCTAssertFalse(index.finished());
  }
}

/**
 Run the real `Sample::Generator` (cubic interpolation, looping) over a synthetic sample whose value encodes its index,
 and compare every output with a reference model of the correct behaviour:
 - the index wraps into the loop by modulo (any increment);
 - interpolation reads at or past the loop end map back into the loop (`endLoop + 1` -> `startLoop + 1`);
 - the sample before the loop start is the loop end only once playback has wrapped.
 */
static void checkLoopingAgainstReference(Float increment, int steps)
{
  const size_t startLoop = 16, endLoop = 32, end = 64;
  const size_t loopSize = endLoop - startLoop;
  SampleVector values(end + SF2::Render::Zone::NormalizedSampleSpan::sizePaddingAfterEnd + 1);
  for (size_t i = 0; i < values.size(); ++i) values[i] = int16_t(i * 100);

  SampleHeader header{0, uint32_t(end), uint32_t(startLoop), uint32_t(endLoop), 48'000, 69, 0};
  auto span = std::make_shared<SF2::Render::Zone::NormalizedSampleSpan>(values, 0, header);
  State::State state(48'000.0);
  Sample::Generator generator;
  generator.configure(std::move(span));
  generator.start(state);

  size_t whole = 0;
  Float partial = 0_F;
  bool looped = false;
  auto sampleAt = [&](size_t i) { if (i >= endLoop) i = startLoop + (i - endLoop) % loopSize; return values[i]; };
  auto before = [&](size_t i) -> Float {
    if (looped && i == startLoop) return values[endLoop - 1];
    return i == 0 ? 0_F : values[i - 1];
  };

  for (int step = 0; step < steps; ++step) {
    Float expected = DSPHeaders::DSP::Interpolation::cubic4thOrder(partial, before(whole), sampleAt(whole),
                                                                   sampleAt(whole + 1), sampleAt(whole + 2)) *
                     SF2::Render::Zone::NormalizedSampleSpan::normalizationScale;
    Float actual = generator.generate(increment, true);
    XCTAssertEqualWithAccuracy(actual, expected, 1.0e-6, @"increment %f step %d whole %zu", increment, step, whole);
    XCTAssertTrue(generator.isActive());

    auto wholeIncrement = size_t(increment);
    whole += wholeIncrement;
    partial += increment - Float(wholeIncrement);
    if (partial >= 1_F) {
      auto carry = std::trunc(partial);
      whole += size_t(carry);
      partial -= carry;
    }
    if (whole >= endLoop) {
      whole = startLoop + (whole - endLoop) % loopSize;
      looped = true;
    }
  }
}

- (void)testCubicInterpolationAcrossLoopBoundaries {
  // 1.5 lands on every loop edge with a half-sample position, including the first pass through the loop start.
  checkLoopingAgainstReference(1.5_F, 300);
}

- (void)testCubicInterpolationWithIncrementLargerThanLoop {
  // 40 > the 16-sample loop: the index and the interpolation reads must both wrap by modulo.
  checkLoopingAgainstReference(40.25_F, 300);
}

- (void)testGeneratorFirstSampleHonoursStartOffset {
  // Use a real preset sample. With an increment of exactly 1 and linear interpolation, the first generated value is
  // the sample at the start position, so a start offset of N must yield sample N of the span.
  auto& context = self.contexts->context0;
  auto configs = context.preset(0).find(60, 64);
  XCTAssertFalse(configs.empty());
  const auto& config = configs[0];
  auto span = config.samples();
  XCTAssertGreaterThan(span->size(), size_t(1'000));

  for (int offset : {0, 1, 500}) {
    auto state = context.makeState(config);
    self.sst.setValue(state, GenIndex::startAddressOffset, offset);
    Sample::Generator generator;
    generator.configure(config.samples());
    generator.start(state);
    XCTAssertEqual(generator.generate(1_F, false),
                   Float((*span)[size_t(offset)]) * SF2::Render::Zone::NormalizedSampleSpan::normalizationScale,
                   @"offset %d", offset);
    XCTAssertEqual(generator.generate(1_F, false),
                   Float((*span)[size_t(offset + 1)]) * SF2::Render::Zone::NormalizedSampleSpan::normalizationScale,
                   @"offset %d", offset);
  }
}

@end
