// Copyright © 2026 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"

#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"
#include "SF2Lib/Render/Voice/Sample/Index.hpp"

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
    Sample::Generator generator{Interpolator::linear};
    generator.configure(config.samples());
    generator.start(state);
    XCTAssertEqual(generator.generate(1_F, false), (*span)[size_t(offset)], @"offset %d", offset);
    XCTAssertEqual(generator.generate(1_F, false), (*span)[size_t(offset + 1)], @"offset %d", offset);
  }
}

@end
