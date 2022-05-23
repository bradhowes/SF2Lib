// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

using namespace SF2::MIDI;

@interface ChannelTests : XCTestCase
@property (nonatomic, assign) SF2::Float epsilon;
@end

@implementation ChannelTests

- (void)testChannelKeyPressureValues {
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

- (void)testChannelPitchWheelValue {
  ChannelState channel;
  XCTAssertEqual(0, channel.pitchWheelValue());

  channel.setPitchWheelValue(123);
  XCTAssertEqual(123, channel.pitchWheelValue());
}

- (void)testChannelPitchWheelSensitivity {
  ChannelState channel;
  XCTAssertEqual(200, channel.pitchWheelSensitivity());

  channel.setPitchWheelSensitivity(123);
  XCTAssertEqual(123, channel.pitchWheelSensitivity());
}

- (void)testChannelContinuousControllerValues {
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

@end
