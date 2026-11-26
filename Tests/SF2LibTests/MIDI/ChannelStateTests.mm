// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

using namespace SF2::MIDI;

@interface ChannelStateTests : XCTestCase

@property (nonatomic) SF2::Float epsilon;

@end

@implementation ChannelStateTests

@synthesize epsilon;

- (void)setUp {
  self.epsilon = PresetTestContextBase::epsilonValue();
}

- (void)testInit {
  ChannelState channel;
  for (int key = 0; key < 128; ++key) XCTAssertEqual(0, channel.notePressure(Note(key)));
  XCTAssertEqual(0, channel.channelPressure());
  XCTAssertEqual(8192, channel.pitchWheelValue());
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
  XCTAssertEqual(8192, channel.pitchWheelValue());

  channel.setPitchWheelValue(123);
  XCTAssertEqual(123, channel.pitchWheelValue());

  // Full 14-bit MIDI range is accepted; values outside it are clamped.
  channel.setPitchWheelValue(16383);
  XCTAssertEqual(16383, channel.pitchWheelValue());
  channel.setPitchWheelValue(20000);
  XCTAssertEqual(16383, channel.pitchWheelValue());
  channel.setPitchWheelValue(-1);
  XCTAssertEqual(0, channel.pitchWheelValue());
}

- (void)testPitchWheelSensitivity {
  ChannelState channel;
  XCTAssertEqual(2, channel.pitchWheelSensitivity());

  channel.setPitchWheelSensitivity(123);
  XCTAssertEqual(123, channel.pitchWheelSensitivity());
}

- (void)testRPN0SetsPitchWheelSensitivity {
  // SF2.01 8.2.1: the pitch wheel sensitivity source is "sent from the MIDI RPN 0 pitch wheel sensitivity command".
  // Select RPN 0 with CC 101/100 = 0/0, then send the range in semitones with Data Entry MSB (CC 6).
  ChannelState channel;
  channel.setContinuousControllerValue(ControlChange::rpnMSB, 0);
  channel.setContinuousControllerValue(ControlChange::rpnLSB, 0);
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 12);
  XCTAssertEqual(12, channel.pitchWheelSensitivity());

  // Data Entry LSB (cents) does not change the semitone value.
  channel.setContinuousControllerValue(ControlChange::dataEntryLSB, 50);
  XCTAssertEqual(12, channel.pitchWheelSensitivity());

  // An unrelated controller does not deselect the RPN (unlike the NRPN decoder).
  channel.setContinuousControllerValue(ControlChange::modulationWheelMSB, 64);
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 7);
  XCTAssertEqual(7, channel.pitchWheelSensitivity());
}

- (void)testRPNDataEntryOnlyAppliesToRPN0 {
  ChannelState channel;

  // Nothing selected yet (both RPN and NRPN start as "null")
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 9);
  XCTAssertEqual(2, channel.pitchWheelSensitivity());

  // RPN 1 (fine tuning) is not supported and must not change the sensitivity.
  channel.setContinuousControllerValue(ControlChange::rpnMSB, 0);
  channel.setContinuousControllerValue(ControlChange::rpnLSB, 1);
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 9);
  XCTAssertEqual(2, channel.pitchWheelSensitivity());

  // The RPN null value (127/127) deselects.
  channel.setContinuousControllerValue(ControlChange::rpnLSB, 0);
  channel.setContinuousControllerValue(ControlChange::rpnMSB, 127);
  channel.setContinuousControllerValue(ControlChange::rpnLSB, 127);
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 9);
  XCTAssertEqual(2, channel.pitchWheelSensitivity());

  // Selecting an NRPN after RPN 0 sends Data Entry to the NRPN instead.
  channel.setContinuousControllerValue(ControlChange::rpnMSB, 0);
  channel.setContinuousControllerValue(ControlChange::rpnLSB, 0);
  channel.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channel.setContinuousControllerValue(ControlChange::nrpnLSB, 51); // coarseTune
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 70);
  XCTAssertEqual(2, channel.pitchWheelSensitivity());

  // Reset restores the default.
  channel.setContinuousControllerValue(ControlChange::rpnMSB, 0);
  channel.setContinuousControllerValue(ControlChange::rpnLSB, 0);
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 24);
  XCTAssertEqual(24, channel.pitchWheelSensitivity());
  channel.reset();
  XCTAssertEqual(2, channel.pitchWheelSensitivity());
}

- (void)testContinuousControllerValues {
  ChannelState channel;

  channel.setContinuousControllerValue(ControlChange::bankSelectMSB, 123);
  XCTAssertEqual(123, channel.continuousControllerValue(ControlChange::bankSelectMSB));

  channel.setContinuousControllerValue(ControlChange::bankSelectMSB, 31);
  XCTAssertEqual(31, channel.continuousControllerValue(ControlChange::bankSelectMSB));

  for (int index = 0; index < 128; ++index) {
    if (index < 0x62 || index > 0x65){
      channel.setContinuousControllerValue(ControlChange(index), uint8_t(index));
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
    channelState.setContinuousControllerValue(ControlChange::nrpnMSB, uint8_t(value));
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

- (void)testUnrelatedControllersDoNotCancelNRPN {
  // SF2.01 9.6.2: only CC 99 / CC 101 change the Data Entry mode. A mod wheel or pedal message between the NRPN select
  // and its Data Entry used to cancel decoding, so the value was silently dropped.
  ChannelState channelState;
  auto index = SF2::Entity::Generator::Index::initialFilterCutoff; // 8
  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 8);
  channelState.setContinuousControllerValue(ControlChange::modulationWheelMSB, 64);
  channelState.setContinuousControllerValue(ControlChange::sustainSwitch, 127);
  channelState.setContinuousControllerValue(ControlChange::volumeMSB, 90);
  XCTAssertTrue(channelState.isActivelyDecoding());
  XCTAssertEqual(size_t(8), channelState.nrpnIndex());

  // 0x2000 + 100 -> +100 steps; initialFilterCutoff uses an NRPN multiplier of 2.
  channelState.setContinuousControllerValue(ControlChange::dataEntryLSB, 100);
  channelState.setContinuousControllerValue(ControlChange::dataEntryMSB, 0x40);
  XCTAssertEqual(200, channelState.nrpnValue(index));

  // The other controllers still took effect.
  XCTAssertEqual(64, channelState.continuousControllerValue(ControlChange::modulationWheelMSB));
  XCTAssertTrue(channelState.pedalState().sustainPedalActive);
}

- (void)testResetControllersFollowsRP015 {
  // CC 121 (Reset All Controllers) as described by MIDI RP-015.
  ChannelState channel;
  channel.setContinuousControllerValue(ControlChange::bankSelectMSB, 5);
  channel.setContinuousControllerValue(ControlChange::modulationWheelMSB, 50);
  channel.setContinuousControllerValue(ControlChange::volumeMSB, 40);
  channel.setContinuousControllerValue(ControlChange::panMSB, 20);
  channel.setContinuousControllerValue(ControlChange::expressionMSB, 30);
  channel.setContinuousControllerValue(ControlChange::sustainSwitch, 127);
  channel.setContinuousControllerValue(ControlChange::sostenutoSwitch, 127);
  channel.setContinuousControllerValue(ControlChange::softPedalSwitch, 127);
  channel.setContinuousControllerValue(ControlChange::effectsDepth1, 70);
  // Controllers RP-015 lists in neither group are documented as kept.
  channel.setContinuousControllerValue(ControlChange(2), 50);    // breath
  channel.setContinuousControllerValue(ControlChange(8), 30);    // balance
  channel.setContinuousControllerValue(ControlChange(68), 127);  // legato
  channel.setPitchWheelValue(0);
  channel.setChannelPressure(99);
  channel.setNotePressure(60, 77);
  // RPN 0 = 12 semitones, and an SF2 NRPN value for initialFilterCutoff
  channel.setContinuousControllerValue(ControlChange::rpnMSB, 0);
  channel.setContinuousControllerValue(ControlChange::rpnLSB, 0);
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 12);
  channel.setContinuousControllerValue(ControlChange::nrpnMSB, 120);
  channel.setContinuousControllerValue(ControlChange::nrpnLSB, 8);
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 0x41);
  auto nrpnValue = channel.nrpnValue(SF2::Entity::Generator::Index::initialFilterCutoff);
  XCTAssertNotEqual(nrpnValue, 0);

  channel.resetControllers();

  // Reset
  XCTAssertEqual(0, channel.continuousControllerValue(ControlChange::modulationWheelMSB));
  XCTAssertEqual(127, channel.continuousControllerValue(ControlChange::expressionMSB));
  XCTAssertFalse(channel.pedalState().sustainPedalActive);
  XCTAssertFalse(channel.pedalState().sostenutoPedalActive);
  XCTAssertFalse(channel.pedalState().softPedalActive);
  XCTAssertEqual(0, channel.continuousControllerValue(ControlChange::sustainSwitch));
  XCTAssertEqual(8192, channel.pitchWheelValue());
  XCTAssertEqual(0, channel.channelPressure());
  XCTAssertEqual(0, channel.notePressure(60));
  XCTAssertEqual(127, channel.continuousControllerValue(ControlChange::rpnMSB));
  XCTAssertEqual(127, channel.continuousControllerValue(ControlChange::nrpnMSB));
  XCTAssertFalse(channel.isActivelyDecoding());

  // Kept
  XCTAssertEqual(5, channel.continuousControllerValue(ControlChange::bankSelectMSB));
  XCTAssertEqual(40, channel.continuousControllerValue(ControlChange::volumeMSB));
  XCTAssertEqual(20, channel.continuousControllerValue(ControlChange::panMSB));
  XCTAssertEqual(70, channel.continuousControllerValue(ControlChange::effectsDepth1));
  XCTAssertEqual(50, channel.continuousControllerValue(ControlChange(2)));
  XCTAssertEqual(30, channel.continuousControllerValue(ControlChange(8)));
  XCTAssertEqual(127, channel.continuousControllerValue(ControlChange(68)));
  XCTAssertEqual(12, channel.pitchWheelSensitivity());
  XCTAssertEqual(nrpnValue, channel.nrpnValue(SF2::Entity::Generator::Index::initialFilterCutoff));

  // With the parameter numbers null, Data Entry changes nothing.
  channel.setContinuousControllerValue(ControlChange::dataEntryMSB, 3);
  XCTAssertEqual(12, channel.pitchWheelSensitivity());
  XCTAssertEqual(nrpnValue, channel.nrpnValue(SF2::Entity::Generator::Index::initialFilterCutoff));
}

- (void)testNRPNIndexing {
  ChannelState channelState;

  channelState.setContinuousControllerValue(ControlChange::nrpnMSB, 120);

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 31);
  XCTAssertEqual(size_t(31), channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 60);
  XCTAssertEqual(size_t(60), channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 100);
  XCTAssertEqual(size_t(160), channelState.nrpnIndex());
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 100);
  XCTAssertEqual(size_t(260), channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 101);
  XCTAssertEqual(size_t(1260), channelState.nrpnIndex());
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 101);
  XCTAssertEqual(size_t(2260), channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 102);
  XCTAssertEqual(size_t(12260), channelState.nrpnIndex());
  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 102);
  XCTAssertEqual(size_t(22260), channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::nrpnLSB, 1);
  XCTAssertEqual(size_t(1), channelState.nrpnIndex());
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
  XCTAssertEqual(size_t(56), channelState.nrpnIndex());

  channelState.setContinuousControllerValue(ControlChange::dataEntryLSB, 123);
  channelState.setContinuousControllerValue(ControlChange::dataEntryMSB, 21);
  z = ((21 << 7) | 123) - 8192;
  XCTAssertEqual(channelState.nrpnValue(SF2::Entity::Generator::Index(56)), z);
  XCTAssertEqual(size_t(56), channelState.nrpnIndex());

  // An LSB arriving after the MSB refines the current value immediately.
  channelState.setContinuousControllerValue(ControlChange::dataEntryMSB, 20);
  channelState.setContinuousControllerValue(ControlChange::dataEntryLSB, 5);
  z = ((20 << 7) | 5) - 8192;
  XCTAssertEqual(channelState.nrpnValue(SF2::Entity::Generator::Index(56)), z);
}

@end
