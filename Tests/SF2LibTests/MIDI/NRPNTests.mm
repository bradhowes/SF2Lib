// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SF2Lib/MIDI/NRPN.hpp"

using namespace SF2;
using namespace SF2::MIDI;

struct NRPNTestPoint {
  NRPNTestPoint(NRPN& out) : out_{out} {}
  NRPN& out_;
  size_t index() { return out_.index_; }
  int value(int index) { return out_.nrpnValues_[index]; }
};

@interface NRPNTests : XCTestCase
@end

@implementation NRPNTests {
  Float epsilon;
}

- (void)setUp {
  epsilon = 1.0e-9;
}

- (void)testActivation {
  ChannelState channelState;
  NRPN nrpn{channelState};

  XCTAssertFalse(nrpn.isActive());
  nrpn.process(MIDI::ControlChange::nprnMSB, 119);
  XCTAssertFalse(nrpn.isActive());
  nrpn.process(MIDI::ControlChange::nprnMSB, 120);
  XCTAssertTrue(nrpn.isActive());
  nrpn.process(MIDI::ControlChange::nprnMSB, 119);
  XCTAssertFalse(nrpn.isActive());
  nrpn.process(MIDI::ControlChange::nprnMSB, 120);
  XCTAssertTrue(nrpn.isActive());
  nrpn.process(MIDI::ControlChange::rpnMSB, 120);
  XCTAssertFalse(nrpn.isActive());
}

- (void)testIndexing {
  ChannelState channelState;
  NRPN nrpn{channelState};
  NRPNTestPoint tp{nrpn};

  nrpn.process(MIDI::ControlChange::nprnMSB, 120);
  nrpn.process(MIDI::ControlChange::nprnLSB, 60);
  XCTAssertEqual(60, tp.index());

  nrpn.process(MIDI::ControlChange::nprnLSB, 100);
  XCTAssertEqual(160, tp.index());
  nrpn.process(MIDI::ControlChange::nprnLSB, 100);
  XCTAssertEqual(260, tp.index());

  nrpn.process(MIDI::ControlChange::nprnLSB, 101);
  XCTAssertEqual(1260, tp.index());
  nrpn.process(MIDI::ControlChange::nprnLSB, 101);
  XCTAssertEqual(2260, tp.index());

  nrpn.process(MIDI::ControlChange::nprnLSB, 102);
  XCTAssertEqual(12260, tp.index());
  nrpn.process(MIDI::ControlChange::nprnLSB, 102);
  XCTAssertEqual(22260, tp.index());
}

- (void)testOutOfRangeIndexing {
  ChannelState channelState;
  NRPN nrpn{channelState};
  nrpn.process(MIDI::ControlChange::nprnMSB, 120);
  nrpn.process(MIDI::ControlChange::nprnLSB, 60);
  XCTAssertTrue(nrpn.isActive());
  XCTAssertNoThrow(nrpn.process(MIDI::ControlChange::dataEntryMSB, 123));
}

- (void)testSetValue {
  ChannelState channelState;
  NRPN nrpn{channelState};
  NRPNTestPoint tp{nrpn};

  nrpn.process(MIDI::ControlChange::nprnMSB, 120);
  nrpn.process(MIDI::ControlChange::nprnLSB, 56);
  nrpn.process(MIDI::ControlChange::dataEntryMSB, 123);
  auto z = (123 << 7) - 8192;
  XCTAssertEqual(nrpn.values()[56], z);
  XCTAssertEqual(0, tp.index());

  channelState.setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 123);
  nrpn.process(MIDI::ControlChange::nprnLSB, 56);
  nrpn.process(MIDI::ControlChange::dataEntryMSB, 21);
  z = ((21 << 7) | 123) - 8192;
  XCTAssertEqual(nrpn.values()[56], z);
  XCTAssertEqual(0, tp.index());
}

@end
