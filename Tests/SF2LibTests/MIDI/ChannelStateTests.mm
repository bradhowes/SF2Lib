// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "../SampleBasedContexts.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

using namespace SF2::MIDI;

@interface ChannelStateTests : XCTestCase {
  SF2::Float epsilon;
}
@end

@implementation ChannelStateTests

- (void)setUp {
  epsilon = PresetTestContextBase::epsilonValue();
}

- (void)testInit {
  ChannelState channel;
  for (int key = 0; key < 128; ++key) XCTAssertEqual(0, channel.notePressure(Note(key)));
  XCTAssertEqual(0, channel.channelPressure());
  XCTAssertEqual(4096, channel.pitchWheelValue());
  XCTAssertEqual(2, channel.pitchWheelSensitivity());

  XCTAssertFalse(channel.pedalState().softPedalActive);
  XCTAssertFalse(channel.pedalState().sostenutoPedalActive);
  XCTAssertFalse(channel.pedalState().sustainPedalActive);

  for (int cc = 0; cc < 128; ++cc) {
    int expectedValue = 0;
    auto CC{ControlChange(cc)};
    switch (CC) {
      case ControlChange::volumeMSB: expectedValue = 100; break;
      case ControlChange::balanceMSB: expectedValue = 64; break;
      case ControlChange::panMSB: expectedValue = 64; break;

      case ControlChange::expressionMSB: expectedValue = 127; break;
      case ControlChange::expressionLSB: expectedValue = 127; break;

      case ControlChange::soundControl1: expectedValue = 64; break;
      case ControlChange::soundControl2: expectedValue = 64; break;
      case ControlChange::soundControl3: expectedValue = 64; break;
      case ControlChange::soundControl4: expectedValue = 64; break;
      case ControlChange::soundControl5: expectedValue = 64; break;
      case ControlChange::soundControl6: expectedValue = 64; break;
      case ControlChange::soundControl7: expectedValue = 64; break;
      case ControlChange::soundControl8: expectedValue = 64; break;
      case ControlChange::soundControl9: expectedValue = 64; break;
      case ControlChange::soundControl10: expectedValue = 64; break;

      case ControlChange::nrpnLSB: expectedValue = 127; break;
      case ControlChange::nrpnMSB: expectedValue = 127; break;
      case ControlChange::rpnLSB: expectedValue = 127; break;
      case ControlChange::rpnMSB: expectedValue = 127; break;
      default: break;
    }

    std::cout << cc << ' ' << expectedValue << ' ' << channel.continuousControllerValue(CC) << '\n';
    XCTAssertEqual(expectedValue, channel.continuousControllerValue(CC), @"CC: %d", cc);
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
  XCTAssertEqual(4096, channel.pitchWheelValue());

  channel.setPitchWheelValue(123);
  XCTAssertEqual(123, channel.pitchWheelValue());
}

- (void)testPitchWheelSensitivity {
  ChannelState channel;
  XCTAssertEqual(2, channel.pitchWheelSensitivity());

  channel.setPitchWheelSensitivity(123);
  XCTAssertEqual(123, channel.pitchWheelSensitivity());
}

- (void)testContinuousControllerValues {
  ChannelState channel;

  channel.setContinuousControllerValue(ControlChange::bankSelectMSB, 123);
  XCTAssertEqual(123, channel.continuousControllerValue(ControlChange::bankSelectMSB));

  channel.setContinuousControllerValue(ControlChange::bankSelectMSB, 31);
  XCTAssertEqual(31, channel.continuousControllerValue(ControlChange::bankSelectMSB));

  for (int index = 0; index < 128; ++index) {
    if (index < 0x62 || index > 0x65){
      channel.setContinuousControllerValue(ControlChange(index), index);
    }
  }

  for (int index = 0; index < 128; index += 10) {
    if (index < 0x62 || index > 0x65) {
      XCTAssertEqual(index, channel.continuousControllerValue(ControlChange(index)));
    }
  }

  channel.setContinuousControllerValue(ControlChange::sustainSwitch, 63);
  XCTAssertFalse(channel.pedalState().sustainPedalActive);
  channel.setContinuousControllerValue(ControlChange::sustainSwitch, 64);
  XCTAssertTrue(channel.pedalState().sustainPedalActive);

  channel.setContinuousControllerValue(ControlChange::sostenutoSwitch, 63);
  XCTAssertFalse(channel.pedalState().sostenutoPedalActive);
  channel.setContinuousControllerValue(ControlChange::sostenutoSwitch, 64);
  XCTAssertTrue(channel.pedalState().sostenutoPedalActive);

  channel.setContinuousControllerValue(ControlChange::softPedalSwitch, 63);
  XCTAssertFalse(channel.pedalState().softPedalActive);
  channel.setContinuousControllerValue(ControlChange::softPedalSwitch, 64);
  XCTAssertTrue(channel.pedalState().softPedalActive);
}

- (void)testNRPNActivation {
  ChannelState channelState;

  XCTAssertFalse(channelState.isActivelyDecoding());

  // Only activate on 120 nrpnMSB
  for (auto value = 0; value < 128; ++ value) {
    channelState.setContinuousControllerValue(ControlChange::nrpnMSB, value);
    XCTAssertEqual(channelState.isActivelyDecoding(), value == 120);
  }

  // Deactivate on non-120 nrpnMSB
  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 119);
  XCTAssertFalse(channelState.isActivelyDecoding());

  // Deactivate on any rpnMSB
  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(ControlChange::rpnMSB, 120);
  XCTAssertFalse(channelState.isActivelyDecoding());

  // Deactivate on any rpnLSB
  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(ControlChange::rpnLSB, 120);
  XCTAssertFalse(channelState.isActivelyDecoding());

  // Data entry LSB does not affect activation
  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(ControlChange::dataEntryLSB, 120);
  XCTAssertTrue(channelState.isActivelyDecoding());
}

- (void)testNRPNIndexing {
  ChannelState channelState;

  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 31);
  XCTAssertEqual(31, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 60);
  XCTAssertEqual(60, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 100);
  XCTAssertEqual(160, channelState.nrpnIndex());
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 100);
  XCTAssertEqual(260, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 101);
  XCTAssertEqual(1260, channelState.nrpnIndex());
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 101);
  XCTAssertEqual(2260, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 102);
  XCTAssertEqual(12260, channelState.nrpnIndex());
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 102);
  XCTAssertEqual(22260, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 1);
  XCTAssertEqual(1, channelState.nrpnIndex());
}

- (void)testOutOfRangeNRPNIndexing {
  ChannelState channelState;
  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 60);
  XCTAssertTrue(channelState.isActivelyDecoding());
  XCTAssertNoThrow(channelState.setContinuousControllerValue(ControlChange::dataEntryMSB, 123));
}

- (void)testNRPNSetValue {
  ChannelState channelState;
  XCTAssertEqual(channelState.nrpnValue(SF2::Entity::Generator::Index(56)), 0);
  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 56);
  channelState.setContinuousControllerValue(ControlChange::dataEntryLSB, 0);
  channelState.setContinuousControllerValue(ControlChange::dataEntryMSB, 123);
  auto z = (123 << 7) - 8192;
  XCTAssertEqual(channelState.nrpnValue(SF2::Entity::Generator::Index(56)), z);
  XCTAssertEqual(56, channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::dataEntryLSB, 123);
  channelState.setContinuousControllerValue(ControlChange::dataEntryMSB, 21);
  z = ((21 << 7) | 123) - 8192;
  XCTAssertEqual(channelState.nrpnValue(SF2::Entity::Generator::Index(56)), z);
  XCTAssertEqual(56, channelState.nrpnIndex());
}

@end
