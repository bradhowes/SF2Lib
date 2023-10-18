// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Render/Preset.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Voice;
using namespace SF2::Entity::Generator;
using namespace SF2::Entity::Modulator;

@interface StateTests : SamplePlayingTestCase
@end

@implementation StateTests

- (void)testInit {
  auto state{contexts.context2.makeState(0, 69 + 24, 64)};

  XCTAssertEqual(      0, state.unmodulated(Index::startAddressOffset));
  XCTAssertEqual(      0, state.unmodulated(Index::endAddressOffset));
  XCTAssertEqual(  9'023, state.unmodulated(Index::initialFilterCutoff));
  XCTAssertEqual(-12'000, state.unmodulated(Index::delayModulatorLFO));
  XCTAssertEqual(-12'000, state.unmodulated(Index::delayVibratoLFO));
  XCTAssertEqual(-12'000, state.unmodulated(Index::attackModulatorEnvelope));
  XCTAssertEqual(-12'000, state.unmodulated(Index::holdModulatorEnvelope));
  XCTAssertEqual(-12'000, state.unmodulated(Index::decayModulatorEnvelope));
  XCTAssertEqual(-12'000, state.unmodulated(Index::releaseModulatorEnvelope));
  XCTAssertEqual(-12'000, state.unmodulated(Index::delayVolumeEnvelope));
  XCTAssertEqual(-12'000, state.unmodulated(Index::attackVolumeEnvelope));
  XCTAssertEqual(-12'000, state.unmodulated(Index::holdVolumeEnvelope));
  XCTAssertEqual(-12'000, state.unmodulated(Index::decayVolumeEnvelope));
  XCTAssertEqual(  2'041, state.unmodulated(Index::releaseVolumeEnvelope));
  XCTAssertEqual(     -1, state.unmodulated(Index::forcedMIDIKey));
  XCTAssertEqual(     -1, state.unmodulated(Index::forcedMIDIVelocity));
  XCTAssertEqual(    100, state.unmodulated(Index::scaleTuning));
  XCTAssertEqual(     -1, state.unmodulated(Index::overridingRootKey));
}

- (void)testKey {
  State::State state{contexts.context2.makeState(0, 64, 32)};
  XCTAssertEqual(64, state.key());
  sst.setValue(state, Index::forcedMIDIKey, 1);
  XCTAssertEqual(1, state.key());
}

- (void)testVelocity {
  State::State state{contexts.context2.makeState(0, 64, 32)};
  XCTAssertEqual(32, state.velocity());
  sst.setValue(state, Index::forcedMIDIVelocity, 0);
  XCTAssertEqual(0, state.velocity());
}

- (void)testModulatedValue {
  State::State state{contexts.context2.makeState(0, 60, 32)};
  sst.setValue(state, Index::holdVolumeEnvelope, 100);
  sst.setAdjustment(state, Index::holdVolumeEnvelope, 0);
  XCTAssertEqualWithAccuracy(100.0, state.modulated(Index::holdVolumeEnvelope), 0.000001);
  sst.setAdjustment(state, Index::holdVolumeEnvelope, 50);
  XCTAssertEqualWithAccuracy(150.0, state.modulated(Index::holdVolumeEnvelope), 0.000001);
}

- (void)testInitialAttenuationValues {
  State::State state{contexts.context2.makeState(0, 60, 32)};
  XCTAssertEqual(100, state.channelState().continuousControllerValue(MIDI::ControlChange(7)));
  XCTAssertEqualWithAccuracy(280.982985437, state.modulated(Index::initialAttenuation), 0.000001);
}

- (void)testStateDump {
  State::State state{contexts.context2.makeState(0, 60, 32)};
  state.dump();
}

- (void)testInvalidModulatorIsIgnored {
  State::State state{contexts.context2.makeState(0, 60, 32)};
  XCTAssertEqual(10, state.modulatorCount());

  Source bad1(Source::GeneralIndex(1));
  Modulator badMod1(bad1, Index::initialAttenuation, 123);
  sst.addModulator(state, badMod1);
  XCTAssertEqual(10, state.modulatorCount());
}

- (void)testDuplicateModulatorAmountIsAcquired {
  State::State state{contexts.context2.makeState(0, 60, 32)};

  auto mod = Modulator(Source(Source::GeneralIndex::noteOnVelocity).negative().concave(),
                       Index::initialAttenuation,
                       345);
  sst.addModulator(state, mod);
  state.updateStateMods();
  XCTAssertEqual(10, state.modulatorCount());
  XCTAssertEqual(100, state.channelState().continuousControllerValue(MIDI::ControlChange(7)));
  XCTAssertEqualWithAccuracy(127.577963886, state.modulated(Index::initialAttenuation), 0.000001);
}

- (void)testAddingCustomModulator {
  State::State state{contexts.context2.makeState(0, 60, 32)};
  auto mod = Modulator(Source(Source::GeneralIndex::noteOnKey).negative().concave(),
                       Index::initialAttenuation,
                       -123);
  sst.addModulator(state, mod);
  state.updateStateMods();
  XCTAssertEqual(11, state.modulatorCount());
  XCTAssertEqual(100, state.channelState().continuousControllerValue(MIDI::ControlChange(7)));
  XCTAssertEqualWithAccuracy(264.29329632, state.modulated(Index::initialAttenuation), 0.000001);
}

@end
