// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>
#include <memory>

#include "SampleBasedContexts.hpp"

#include "SF2File/Entity/Generator/Index.hpp"
#include "SF2File/Entity/Modulator/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/Modulator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"

using namespace SF2;
using namespace SF2::Entity::Modulator;
using namespace SF2::Render;
using namespace SF2::Render::Voice;
using namespace SF2::Entity::Generator;

@interface ModulatorTests : SamplePlayingTestCase
@property (nonatomic) MIDI::ChannelState* channelState;
@property (nonatomic) State::State* state;
@end

@implementation ModulatorTests

@synthesize channelState;
@synthesize state;

- (void)setUp {
  [super setUp];
  self.epsilon = PresetTestContextBase::epsilonValue();
  self.channelState = new MIDI::ChannelState();
  self.state = new State::State(44100.0, *self.channelState);
}

- (void)tearDown {}

- (void)testKeyVelocityToInitialAttenuation {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[0]};
  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, -1);

  State::Modulator modulator{config};
  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, 127);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 0.0, self.epsilon);

  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, 64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 119.049498788827904, self.epsilon);

  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, 1);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 841.521488382382699, self.epsilon);

  // std::cout << modulator.description() << '\n';
  XCTAssertEqual("Sv: velocity(uni/+-/concave) Av: none(uni/-+/linear) dest: initialAttenuation amount: 960 trans: linear",
                 modulator.description());
}

- (void)testKeyVelocityToFilterCutoff {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[1]};
  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, -1);

  State::Modulator modulator{config};
  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, 127);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), -18.75, self.epsilon);

  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, 64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), -1200.0, self.epsilon);

  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, 1);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), config.amount() * 127.0 / 128.0, self.epsilon);
}

- (void)testChannelPressureToVibratoLFOPitchDepth {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[2]};
  State::Modulator modulator{config};
  self.channelState->setChannelPressure(0);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 0.0, self.epsilon);

  self.channelState->setChannelPressure(64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 25.0, self.epsilon);

  self.channelState->setChannelPressure(127);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), config.amount() * 127.0 / 128.0, self.epsilon);
}

- (void)testCC1ToVibratoLFOPitchDepth {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[3]};
  XCTAssertEqual(1, config.source().ccIndex().value);
  State::Modulator modulator{config};

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::modulationWheelMSB, 0);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 0.0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::modulationWheelMSB, 64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 25.0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::modulationWheelMSB, 127);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), config.amount() * 127.0 / 128.0, self.epsilon);
}

- (void)testCC7ToInitialAttenuation {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[4]};
  XCTAssertEqual(7, config.source().ccIndex().value);

  State::Modulator modulator{config};

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::volumeMSB, 0);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 960.0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::volumeMSB, 64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 119.049498788827904, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::volumeMSB, 127);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 0.0, self.epsilon);
}

- (void)testCC10ToPanPosition {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[5]};
  XCTAssertEqual(10, config.source().ccIndex().value);
  State::Modulator modulator{config};

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::panMSB, 0);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), -500, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::panMSB, 64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::panMSB, 127);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state),
                             config.amount() * DSPHeaders::DSP::unipolarToBipolar(127.0 / 128.0),
                             self.epsilon);
}

- (void)testCC11ToInitialAttenuation {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[6]};
  XCTAssertEqual(11, config.source().ccIndex().value);
  State::Modulator modulator{config};

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::expressionMSB, 0);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 960.0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::expressionMSB, 64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 119.049498788827904, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::expressionMSB, 127);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 0.0, self.epsilon);
}

- (void)testCC91ToReverbSend {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[7]};
  XCTAssertEqual(91, config.source().ccIndex().value);
  State::Modulator modulator{config};

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth1, 0);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 0.0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth1, 64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 100.0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth1, 127);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), config.amount() * 127.0 / 128.0, self.epsilon);
}

- (void)testCC93ToChorusSend {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[8]};
  XCTAssertEqual(93, config.source().ccIndex().value);
  State:: Modulator modulator{config};

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth3, 0);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 0.0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth3, 64);
  XCTAssertEqualWithAccuracy(modulator.value(*self.state), 100.0, self.epsilon);

  self.channelState->setContinuousControllerValue(MIDI::ControlChange::effectsDepth3, 127);
  XCTAssertEqualWithAccuracy( modulator.value(*self.state), config.amount() * 127.0 / 128.0, self.epsilon);
}

- (void)testPitchWheelToInitialPitch {
  const Entity::Modulator::Modulator& config{Entity::Modulator::Modulator::defaults[9]};
  XCTAssertEqual(Entity::Modulator::Source::GeneralIndex::pitchWheel, config.source().generalIndex());
  State::Modulator modulator{config};

  self.channelState->setPitchWheelSensitivity(0);

  self.channelState->setPitchWheelValue(0);
  XCTAssertEqualWithAccuracy( modulator.value(*self.state), 0.0, self.epsilon);
  self.channelState->setPitchWheelValue(64);
  XCTAssertEqualWithAccuracy( modulator.value(*self.state), 0.0, self.epsilon);
  self.channelState->setPitchWheelValue(127);
  XCTAssertEqualWithAccuracy( modulator.value(*self.state), 0.0, self.epsilon);

  self.channelState->setPitchWheelSensitivity(127);

  self.channelState->setPitchWheelValue(0);
  XCTAssertEqualWithAccuracy( modulator.value(*self.state), -12600.78125, self.epsilon);
  self.channelState->setPitchWheelValue(4096);
  XCTAssertEqualWithAccuracy( modulator.value(*self.state), 0.0, self.epsilon);
  self.channelState->setPitchWheelValue(SF2::MIDI::ChannelState::maxPitchWheelValue);
  XCTAssertEqualWithAccuracy( modulator.value(*self.state), 12597.7048873901367, self.epsilon);
}

- (void)testKeyValueProvider {
  auto src = Source(Source::GeneralIndex::noteOnKey);
  State::Modulator mod{Modulator(src, Index::sustainVolumeEnvelope, 3.0, Source(), Transformer())};
  XCTAssertEqualWithAccuracy(0.0, mod.value(*self.state), self.epsilon);
  self.sst.setValue(*self.state, Index::forcedMIDIKey, 64);
  XCTAssertEqualWithAccuracy(1.5, mod.value(*self.state), self.epsilon);
  self.sst.setValue(*self.state, Index::forcedMIDIKey, 127);
  XCTAssertEqualWithAccuracy(2.9765625, mod.value(*self.state), self.epsilon);
}

- (void)testVelocityValueProvider {
  auto src = Source(Source::GeneralIndex::noteOnVelocity);
  State::Modulator mod{Modulator(src, Index::sustainVolumeEnvelope, 3.0, Source(), Transformer())};
  XCTAssertEqualWithAccuracy(0.0, mod.value(*self.state), self.epsilon);
  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, 64);
  XCTAssertEqualWithAccuracy(1.5, mod.value(*self.state), self.epsilon);
  self.sst.setValue(*self.state, Index::forcedMIDIVelocity, 127);
  XCTAssertEqualWithAccuracy(2.9765625, mod.value(*self.state), self.epsilon);
}

- (void)testKeyPressureValueProvider {
  auto src = Source(Source::GeneralIndex::keyPressure);
  State::Modulator mod{Modulator(src, Index::sustainVolumeEnvelope, 3.0, Source(), Transformer())};
  XCTAssertEqualWithAccuracy(0.0, mod.value(*self.state), self.epsilon);
  self.sst.setValue(*self.state, Index::forcedMIDIKey, 100);
  self.channelState->setNotePressure(100, 64);
  XCTAssertEqualWithAccuracy(1.5, mod.value(*self.state), self.epsilon);
  self.channelState->setNotePressure(100, 127);
  XCTAssertEqualWithAccuracy(2.9765625, mod.value(*self.state), self.epsilon);
}

@end
