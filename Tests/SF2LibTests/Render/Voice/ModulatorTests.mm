// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/Entity/Modulator/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Entity::Modulator;
using namespace SF2::Render;
using namespace SF2::Render::Voice;
using namespace SF2::Entity::Generator;

@interface ModulatorTests : XCTestCase {
  Float epsilon;
  MIDI::ChannelState* channelState;
  State::State* state;
};
@end

@implementation ModulatorTests

- (void)setUp {
  epsilon = 1.0e-3f;
  channelState = new MIDI::ChannelState();
  state = new State::State(44100.0, *channelState);
}

- (void)tearDown {
  delete state;
  delete channelState;
}

- (void)testKeyVelocityToInitialAttenuation {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[0]};
  state->setValue(Index::forcedMIDIVelocity, -1);

  State::Modulator modulator{config, *state};
  state->setValue(Index::forcedMIDIVelocity, 127);
  XCTAssertEqualWithAccuracy(modulator.value(), 0.0, epsilon);

  state->setValue(Index::forcedMIDIVelocity, 64);
  XCTAssertEqualWithAccuracy(modulator.value(), 119.049498789, epsilon);

  state->setValue(Index::forcedMIDIVelocity, 1);
  XCTAssertEqualWithAccuracy(modulator.value(), 841.521488382, epsilon);

  // std::cout << modulator.description() << '\n';
  XCTAssertEqual("Sv: velocity(uni/+-/concave) Av: none(uni/-+/linear) dest: initialAttenuation amount: 960 trans: linear",
                 modulator.description());
}

- (void)testKeyVelocityToFilterCutoff {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[1]};
  state->setValue(Index::forcedMIDIVelocity, -1);

  State::Modulator modulator{config, *state};
  state->setValue(Index::forcedMIDIVelocity, 127);
  XCTAssertEqualWithAccuracy(modulator.value(), -18.75, epsilon);

  state->setValue(Index::forcedMIDIVelocity, 64);
  XCTAssertEqualWithAccuracy(modulator.value(), -1200.0, epsilon);

  state->setValue(Index::forcedMIDIVelocity, 1);
  XCTAssertEqualWithAccuracy(modulator.value(), config.amount() * 127.0 / 128.0, epsilon);
}

- (void)testChannelPressureToVibratoLFOPitchDepth {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[2]};
  State::Modulator modulator{config, *state};
  channelState->setChannelPressure(0);
  XCTAssertEqualWithAccuracy(modulator.value(), 0.0, epsilon);

  channelState->setChannelPressure(64);
  XCTAssertEqualWithAccuracy(modulator.value(), 25.0, epsilon);

  channelState->setChannelPressure(127);
  XCTAssertEqualWithAccuracy(modulator.value(), config.amount() * 127.0 / 128.0, epsilon);
}

- (void)testCC1ToVibratoLFOPitchDepth {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[3]};
  XCTAssertEqual(1, config.source().ccIndex());
  State::Modulator modulator{config, *state};

  channelState->setContinuousControllerValue(MIDI::ControlChange::modulationWheelMSB, 0);
  XCTAssertEqualWithAccuracy(modulator.value(), 0.0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::modulationWheelMSB, 64);
  XCTAssertEqualWithAccuracy(modulator.value(), 25.0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::modulationWheelMSB, 127);
  XCTAssertEqualWithAccuracy(modulator.value(), config.amount() * 127.0 / 128.0, epsilon);
}

- (void)testCC7ToInitialAttenuation {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[4]};
  XCTAssertEqual(7, config.source().ccIndex());

  State::Modulator modulator{config, *state};

  channelState->setContinuousControllerValue(MIDI::ControlChange::volumeMSB, 0);
  XCTAssertEqualWithAccuracy(modulator.value(), 960.0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::volumeMSB, 64);
  XCTAssertEqualWithAccuracy(modulator.value(), 119.049498789, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::volumeMSB, 127);
  XCTAssertEqualWithAccuracy(modulator.value(), 0.0, epsilon);
}

- (void)testCC10ToPanPosition {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[5]};
  XCTAssertEqual(10, config.source().ccIndex());
  State::Modulator modulator{config, *state};

  channelState->setContinuousControllerValue(MIDI::ControlChange::panMSB, 0);
  XCTAssertEqualWithAccuracy(modulator.value(), -1000, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::panMSB, 64);
  XCTAssertEqualWithAccuracy(modulator.value(), 0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::panMSB, 127);
  XCTAssertEqualWithAccuracy(modulator.value(), config.amount() * DSPHeaders::DSP::unipolarToBipolar(127.0 / 128.0),
                             epsilon);
}

- (void)testCC11ToInitialAttenuation {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[6]};
  XCTAssertEqual(11, config.source().ccIndex());
  State::Modulator modulator{config, *state};

  channelState->setContinuousControllerValue(MIDI::ControlChange::expressionMSB, 0);
  XCTAssertEqualWithAccuracy(modulator.value(), 960.0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::expressionMSB, 64);
  XCTAssertEqualWithAccuracy(modulator.value(), 119.049498789, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::expressionMSB, 127);
  XCTAssertEqualWithAccuracy(modulator.value(), 0.0, epsilon);
}

- (void)testCC91ToReverbSend {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[7]};
  XCTAssertEqual(91, config.source().ccIndex());
  State::Modulator modulator{config, *state};

  channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth1, 0);
  XCTAssertEqualWithAccuracy(modulator.value(), 0.0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth1, 64);
  XCTAssertEqualWithAccuracy(modulator.value(), 100.0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth1, 127);
  XCTAssertEqualWithAccuracy(modulator.value(), config.amount() * 127.0 / 128.0, epsilon);
}

- (void)testCC93ToChorusSend {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[8]};
  XCTAssertEqual(93, config.source().ccIndex());
  State:: Modulator modulator{config, *state};

  channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth3, 0);
  XCTAssertEqualWithAccuracy(modulator.value(), 0.0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth3, 64);
  XCTAssertEqualWithAccuracy(modulator.value(), 100.0, epsilon);

  channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth3, 127);
  XCTAssertEqualWithAccuracy( modulator.value(), config.amount() * 127.0 / 128.0, epsilon);
}

- (void)testPitchWheelToInitialPitch {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[9]};
  XCTAssertEqual(Entity::Modulator::Source::GeneralIndex::pitchWheel, config.source().generalIndex());
  State::Modulator modulator{config, *state};

  channelState->setPitchWheelSensitivity(0);

  channelState->setPitchWheelValue(0);
  XCTAssertEqualWithAccuracy( modulator.value(), 0.0, epsilon);
  channelState->setPitchWheelValue(64);
  XCTAssertEqualWithAccuracy( modulator.value(), 0.0, epsilon);
  channelState->setPitchWheelValue(127);
  XCTAssertEqualWithAccuracy( modulator.value(), 0.0, epsilon);

  channelState->setPitchWheelSensitivity(127);

  channelState->setPitchWheelValue(0);
  XCTAssertEqualWithAccuracy( modulator.value(), -12600.78125, epsilon);
  channelState->setPitchWheelValue(4096);
  XCTAssertEqualWithAccuracy( modulator.value(), 0.0, epsilon);
  channelState->setPitchWheelValue(SF2::MIDI::ChannelState::maxPitchWheelValue);
  XCTAssertEqualWithAccuracy( modulator.value(), 12597.7048874, epsilon);
}

- (void)testKeyValueProvider {
  auto src = Source(Source::GeneralIndex::noteOnKey);
  State::Modulator mod{Modulator(src, Index::sustainVolumeEnvelope, 3.0, Source(), Transformer()), *state};
  XCTAssertEqualWithAccuracy(0.0, mod.value(), epsilon);
  state->setValue(Index::forcedMIDIKey, 64);
  XCTAssertEqualWithAccuracy(1.5, mod.value(), epsilon);
  state->setValue(Index::forcedMIDIKey, 127);
  XCTAssertEqualWithAccuracy(2.9765625, mod.value(), epsilon);
}

- (void)testVelocityValueProvider {
  auto src = Source(Source::GeneralIndex::noteOnVelocity);
  State::Modulator mod{Modulator(src, Index::sustainVolumeEnvelope, 3.0, Source(), Transformer()), *state};
  XCTAssertEqualWithAccuracy(0.0, mod.value(), epsilon);
  state->setValue(Index::forcedMIDIVelocity, 64);
  XCTAssertEqualWithAccuracy(1.5, mod.value(), epsilon);
  state->setValue(Index::forcedMIDIVelocity, 127);
  XCTAssertEqualWithAccuracy(2.9765625, mod.value(), epsilon);
}

- (void)testKeyPressureValueProvider {
  auto src = Source(Source::GeneralIndex::keyPressure);
  State::Modulator mod{Modulator(src, Index::sustainVolumeEnvelope, 3.0, Source(), Transformer()), *state};
  XCTAssertEqualWithAccuracy(0.0, mod.value(), epsilon);
  state->setValue(Index::forcedMIDIKey, 100);
  channelState->setNotePressure(100, 64);
  XCTAssertEqualWithAccuracy(1.5, mod.value(), epsilon);
  channelState->setNotePressure(100, 127);
  XCTAssertEqualWithAccuracy(2.9765625, mod.value(), epsilon);
}

@end
