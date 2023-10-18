// Copyright © 2022 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>
#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "../../SampleBasedContexts.hpp"

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
  auto state = State::State(48'000.0, channelState);
  auto bounds = Bounds::make(sampleHeaderNoLoop, state);

  XCTAssertEqual(bounds.startPos(), 0);
  XCTAssertEqual(bounds.endPos(), 139 - 11);
  XCTAssertFalse(bounds.hasLoop());
}

- (void)testStartOffset {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0, channelState);

  sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 1);
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
    XCTAssertFalse(bounds.hasLoop());
  }

  sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, -1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }

  sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, 1000);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), bounds.endPos());
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
}

- (void)testStartOffsetCoarse {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0, channelState);
  sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, -32760);
  sst.setValue(state, SF2::Entity::Generator::Index::startAddressCoarseOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 8);
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startAddressOffset, -32761);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 7);
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startAddressCoarseOffset, 0);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startAddressCoarseOffset, 2);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), bounds.endPos());
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
}

- (void)testEndOffset {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0, channelState);

  sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, -1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize() - 1);
  }
  // Positive values are useless here
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
}

- (void)testEndOffsetCoarse {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0, channelState);
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressCoarseOffset, -1);
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 32760);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), 120);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 32761);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), 121);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 32759);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), 119);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 32759 - 130);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), 0);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressOffset, 0);
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressCoarseOffset, -2);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), 0);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endAddressCoarseOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderNoLoop, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.endPos(), sampleHeaderNoLoop.sampleSize());
  }
}

- (void)testStartLoopOffset {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0, channelState);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.startLoopPos(), 43);
    XCTAssertEqual(bounds.endLoopPos(), 90);
    XCTAssertEqual(bounds.endPos(), 128);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, -1);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 42);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, -43);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 0);
    XCTAssertEqual(bounds.endLoopPos(), 90);
    XCTAssertEqual(bounds.endPos(), 128);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 80);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 123);
    XCTAssertEqual(bounds.endLoopPos(), 90);
    XCTAssertEqual(bounds.endPos(), 128);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 90);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 128);
    XCTAssertEqual(bounds.endLoopPos(), 90);
    XCTAssertEqual(bounds.endPos(), 128);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
}

- (void)testStartLoopOffsetCoarse {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0, channelState);
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, 1);
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, -32760);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 43 + 32768 - 32760);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, -1);
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 32750);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 43 - 32768 + 32750);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, 2);
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 0);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 128);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, -2);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 0);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
}

- (void)testEndLoopOffset {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0, channelState);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startPos(), 0);
    XCTAssertEqual(bounds.startLoopPos(), 43);
    XCTAssertEqual(bounds.endLoopPos(), 90);
    XCTAssertEqual(bounds.endPos(), 128);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, 1);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), 91);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, 40);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), 128);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, -1);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), 89);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, -47);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), 43);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::endLoopAddressOffset, -100);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.endLoopPos(), 0);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
}

- (void)testEndLoopOffsetCoarse {
  auto channelState = MIDI::ChannelState();
  auto state = State::State(48'000.0, channelState);
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, 1);
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, -32760);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 43 + 32768 - 32760);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, -1);
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 32750);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 43 - 32768 + 32750);
    XCTAssertEqual(bounds.hasLoop(), true);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, 2);
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressOffset, 0);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 128);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
  sst.setValue(state, SF2::Entity::Generator::Index::startLoopAddressCoarseOffset, -2);
  {
    auto bounds = Bounds::make(sampleHeaderLooped, state);
    XCTAssertEqual(bounds.startLoopPos(), 0);
    XCTAssertEqual(bounds.hasLoop(), false);
  }
}

@end
