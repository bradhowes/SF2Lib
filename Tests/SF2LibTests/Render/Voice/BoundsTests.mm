// Copyright © 2022 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "SampleBasedContexts.hpp"

using namespace SF2;
using namespace SF2::Entity;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Voice::Sample;

static SampleHeader sampleHeaderNoLoop{11, 139, 0, 0, 48'000, 0, 0};
static SampleHeader sampleHeaderLooped{11, 139, 54, 101, 48'000, 0, 0};

@interface BoundsTests : SamplePlayingTestCase
@end

@implementation BoundsTests

- (void)testBasicNoLoop {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);
  auto bounds = Bounds::make(sampleHeaderNoLoop, state);

  XCTAssertEqual(bounds.startPos(), size_t(0));
  XCTAssertEqual(bounds.endPos(), size_t(139 - 11));
  XCTAssertFalse(bounds.hasLoop());
}

- (void)testStartOffset {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);

  self.sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(1));
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
    XCTAssertFalse(bounds.hasLoop());
  }

  self.sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, -1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }

  self.sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, 1000);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), bounds.endPos());
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
}

- (void)testStartOffsetCoarse {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, -32760);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startAddressCoarseOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(8));
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, -32761);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(7));
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startAddressCoarseOffset, 0);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startAddressCoarseOffset, 2);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), bounds.endPos());
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
}

- (void)testEndOffset {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);

  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, -1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize() - 1);
  }
  // Positive values are useless here
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
}

- (void)testEndOffsetCoarse {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressCoarseOffset, -1);
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 32760);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), size_t(120));
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 32761);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), size_t(121));
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 32759);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), size_t(119));
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 32759 - 130);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), size_t(0));
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 0);
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressCoarseOffset, -2);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), size_t(0));
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endAddressCoarseOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
}

- (void)testStartLoopOffset {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.startLoopPos(), size_t(43));
    XCTAssertEqual(bounds.endLoopPos(), size_t(90));
    XCTAssertEqual(bounds.endPos(), size_t(128));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, -1);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(42));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, -43);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(0));
    XCTAssertEqual(bounds.endLoopPos(), size_t(90));
    XCTAssertEqual(bounds.endPos(), size_t(128));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 80);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(123));
    XCTAssertEqual(bounds.endLoopPos(), size_t(90));
    XCTAssertEqual(bounds.endPos(), size_t(128));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 90);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(128));
    XCTAssertEqual(bounds.endLoopPos(), size_t(90));
    XCTAssertEqual(bounds.endPos(), size_t(128));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
}

- (void)testStartLoopOffsetCoarse {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, 1);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, -32760);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(43 + 32768 - 32760));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, -1);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 32750);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(43 - 32768 + 32750));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, 2);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 0);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(128));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, -2);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(0));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
}

- (void)testEndLoopOffset {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startPos(), size_t(0));
    XCTAssertEqual(bounds.startLoopPos(), size_t(43));
    XCTAssertEqual(bounds.endLoopPos(), size_t(90));
    XCTAssertEqual(bounds.endPos(), size_t(128));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), size_t(91));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, 40);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), size_t(128));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, -1);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), size_t(89));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, -47);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), size_t(43));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, -100);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), size_t(0));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
}

- (void)testEndLoopOffsetCoarse {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, 1);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, -32760);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(43 + 32768 - 32760));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, -1);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 32750);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(43 - 32768 + 32750));
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, 2);
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 0);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(128));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  self.sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, -2);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), size_t(0));
    XCTAssertEqual(bounds.hasLoop(), false);
  }
}

@end
