// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

using namespace SF2::MIDI;

@interface ChannelStateTests : XCTestCase
@property (nonatomic, assign) SF2::Float epsilon;
@end

@implementation ChannelStateTests

- (void)testInit {
  ChannelState channel;
  for (int key = 0; key < 128; ++key) XCTAssertEqual(0, channel.notePressure(Note(key)));
  XCTAssertEqual(0, channel.channelPressure());
  XCTAssertEqual(0, channel.pitchWheelValue());
  XCTAssertEqual(200, channel.pitchWheelSensitivity());

  for (int cc = ChannelState::CCMin; cc <= ChannelState::CCMax; ++cc) {
    XCTAssertEqual(0, channel.continuousControllerValue(cc));
  }

  for (auto index : SF2::Entity::Generator::IndexIterator()) {
    XCTAssertEqual(0, channel.nrpnValue(index));
  }
}

- (void)testKeyPressureValues {
  ChannelState channel;
  for (int key = 0; key < 128; ++key) XCTAssertEqual(0, channel.notePressure(Note(key)));

  channel.setNotePressure(64, 3);
  XCTAssertEqual(3, channel.notePressure(64));

  for (int key = 0; key < 128; ++key) channel.setNotePressure(key, 121);
  for (int key = 0; key < 128; ++key) XCTAssertEqual(121, channel.notePressure(key));
}

- (void)testChannelPressureValue {
  ChannelState channel;
  XCTAssertEqual(0, channel.channelPressure());

  channel.setChannelPressure(123);
  XCTAssertEqual(123, channel.channelPressure());
}

- (void)testPitchWheelValue {
  ChannelState channel;
  XCTAssertEqual(0, channel.pitchWheelValue());

  channel.setPitchWheelValue(123);
  XCTAssertEqual(123, channel.pitchWheelValue());
}

- (void)testPitchWheelSensitivity {
  ChannelState channel;
  XCTAssertEqual(200, channel.pitchWheelSensitivity());

  channel.setPitchWheelSensitivity(123);
  XCTAssertEqual(123, channel.pitchWheelSensitivity());
}

- (void)testContinuousControllerValues {
  ChannelState channel;
  for (int index = 0; index < 127; index += 10) XCTAssertEqual(0, channel.continuousControllerValue(index));

  channel.setContinuousControllerValue(SF2::MIDI::ControlChange::bankSelectMSB, 123);
  XCTAssertEqual(123, channel.continuousControllerValue(0));

  channel.setContinuousControllerValue(SF2::MIDI::ControlChange::bankSelectMSB, 456);
  XCTAssertEqual(456, channel.continuousControllerValue(0));

  for (int index = 0; index < 127; index += 10) {
    channel.setContinuousControllerValue(SF2::MIDI::ControlChange(index), -50 + index);
  }

  for (int index = 0; index < 127; index += 10) {
    XCTAssertEqual(-50 + index, channel.continuousControllerValue(index));
  }
}

- (void)testActivation {
  ChannelState channelState;

  XCTAssertFalse(channelState.isActivelyDecoding());
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnMSB, 119);
  XCTAssertFalse(channelState.isActivelyDecoding());
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnMSB, 120);
  XCTAssertTrue(channelState.isActivelyDecoding());
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnMSB, 119);
  XCTAssertFalse(channelState.isActivelyDecoding());
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnMSB, 120);
  XCTAssertTrue(channelState.isActivelyDecoding());
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::rpnMSB, 120);
  XCTAssertFalse(channelState.isActivelyDecoding());
}

- (void)testIndexing {
  ChannelState channelState;

  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 60);
  XCTAssertEqual(60, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 100);
  XCTAssertEqual(160, channelState.nrpnIndex());
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 100);
  XCTAssertEqual(260, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 101);
  XCTAssertEqual(1260, channelState.nrpnIndex());
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 101);
  XCTAssertEqual(2260, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 102);
  XCTAssertEqual(12260, channelState.nrpnIndex());
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 102);
  XCTAssertEqual(22260, channelState.nrpnIndex());
}

- (void)testOutOfRangeIndexing {
  ChannelState channelState;
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 60);
  XCTAssertTrue(channelState.isActivelyDecoding());
  XCTAssertNoThrow(channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::dataEntryMSB, 123));
}

- (void)testSetValue {
  ChannelState channelState;
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 56);
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::dataEntryMSB, 123);
  auto z = (123 << 7) - 8192;
  XCTAssertEqual(channelState.nrpnValue(SF2::Entity::Generator::Index(56)), z);
  XCTAssertEqual(0, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::dataEntryLSB, 123);
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::nrpnLSB, 56);
  channelState.setContinuousControllerValue(SF2::MIDI::ControlChange::dataEntryMSB, 21);
  z = ((21 << 7) | 123) - 8192;
  XCTAssertEqual(channelState.nrpnValue(SF2::Entity::Generator::Index(56)), z);
  XCTAssertEqual(0, channelState.nrpnIndex());
}
@end
