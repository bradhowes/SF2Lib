// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <iostream>
#include <vector>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.hpp"
#include "SF2Util/Base64.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"

using namespace SF2;
using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

@interface EngineTests : SamplePlayingTestCase
@end

@implementation EngineTests

- (void)setUp {
  [super setUp];
  self.epsilon = PresetTestContextBase::epsilon;
  // self.playAudio = YES;
}

- (void)testInit {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertEqual(engine.voiceCount(), size_t(32));
  XCTAssertEqual(engine.activeVoiceCount(), size_t(0));
  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
  XCTAssertFalse(engine.portamentoModeEnabled());
  XCTAssertEqual(size_t(100), engine.portamentoRate());
  XCTAssertTrue(engine.retriggerModeEnabled());
  XCTAssertEqual(Engine::minLastLoadFinished, engine.lastLoadFinishedCounter());
}

- (void)testPortamento {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};

  XCTAssertFalse(engine.portamentoModeEnabled());
  harness.setParameter(ParameterAddress::portamentoModeEnabled, 1.0);
  XCTAssertTrue(engine.portamentoModeEnabled());

  harness.setParameter(ParameterAddress::portamentoRate, 12345);
  XCTAssertEqual(size_t(12345), engine.portamentoRate());

  harness.setParameter(ParameterAddress::portamentoRate, 987);
  XCTAssertEqual(size_t(987), engine.portamentoRate());

  harness.setParameter(ParameterAddress::portamentoModeEnabled, 0.0);
  XCTAssertFalse(engine.portamentoModeEnabled());
}

- (void)testPhonicMode {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};

  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.monophonicModeEnabled());

  harness.setParameter(ParameterAddress::polyphonicModeEnabled, 0.0);
  XCTAssertFalse(engine.polyphonicModeEnabled());
  XCTAssertTrue(engine.monophonicModeEnabled());

  harness.setParameter(ParameterAddress::polyphonicModeEnabled, 1.0);
  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.monophonicModeEnabled());
}

- (void)testOneVoicePerKey {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};

  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());

  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 1.0);
  XCTAssertTrue(engine.oneVoicePerKeyModeEnabled());

  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 0.0);
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
}

- (void)testRetriggering {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};

  XCTAssertTrue(engine.retriggerModeEnabled());

  harness.setParameter(ParameterAddress::retriggerModeEnabled, 0.0);
  XCTAssertFalse(engine.retriggerModeEnabled());

  harness.setParameter(ParameterAddress::retriggerModeEnabled, 1.0);
  XCTAssertTrue(engine.retriggerModeEnabled());
}

- (void)testLoad {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0, 0.0005);

  harness.load(self.contexts->context0.path(), 0);
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0001, 0.0005);

  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqual(engine.presetCount(), size_t(235));
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0002, 0.0005);

  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual(harness.load(self.contexts->context1.path(), 10000), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0003, 0.0005);

  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual(harness.load(self.contexts->context2.path(), 0), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0004, 0.0005);
}

- (void)testUsePresetByIndex {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("Piano 1", engine.activePresetName());
  harness.usePresetWithIndex(1);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 2", engine.activePresetName());
  harness.usePresetWithIndex(2);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 3", engine.activePresetName());
  harness.usePresetWithIndex(9999);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
}

- (void)testUsePresetByBankProgram {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), SF2::IO::File::LoadResponse::ok);

  harness.usePresetWithBankProgram(0, 0);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("Piano 1", engine.activePresetName());
  harness.usePresetWithBankProgram(0, 1);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 2", engine.activePresetName());
  harness.usePresetWithBankProgram(128, 56);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("SFX", engine.activePresetName());
  harness.usePresetWithBankProgram(uint16_t(-1), uint16_t(-1));
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  harness.usePresetWithBankProgram(uint16_t(-1), 0);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  harness.usePresetWithBankProgram(0, uint16_t(-1));
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  harness.usePresetWithBankProgram(129, 0);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  harness.usePresetWithBankProgram(0, 128);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
}

- (void)testRolandPianoChordRenderLinear {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  int cycles = 5;
  AVAudioFrameCount noteOnIndex = 1;
  AVAudioFrameCount chordDuration = 30;
  AVAudioFrameCount noteOffIndex = AVAudioFrameCount(noteOnIndex + chordDuration * 0.75);

  auto mixer{harness.createMixer(12)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  auto playChord = [&](uint8_t note1, uint8_t note2, uint8_t note3, bool sustain) {
    harness.renderUntil(mixer, noteOnIndex);
    harness.sendNoteOn(note1);
    harness.sendNoteOn(note2);
    harness.sendNoteOn(note3);
    harness.renderUntil(mixer, noteOffIndex);
    if (!sustain) {
      harness.sendNoteOff(note1);
      harness.sendNoteOff(note2);
      harness.sendNoteOff(note3);
    }
    noteOnIndex += chordDuration;
    noteOffIndex += chordDuration;
  };

  for (auto count = 0; count < cycles; ++count) {
    playChord(60, 64, 67, false);
    samples.push_back(harness.lastDrySample());
    playChord(60, 65, 69, false);
    samples.push_back(harness.lastDrySample());
    playChord(60, 64, 67, false);
    samples.push_back(harness.lastDrySample());
    playChord(59, 62, 67, false);
    samples.push_back(harness.lastDrySample());
    playChord(60, 64, 67, count == cycles - 1);
    samples.push_back(harness.lastDrySample());
  }

  XCTAssertEqual(size_t(32), engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0585853196680545807, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.139635398983955383, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0656754374504089355, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0630209818482398987, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0279885157942771912, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0638669133186340332, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.13651759922504425, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0657804235816001892, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0629896596074104309, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0280037727206945419, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0638669133186340332, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.13651759922504425, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0657804235816001892, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0629896596074104309, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0280037727206945419, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0638669133186340332, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.13651759922504425, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0657804235816001892, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0629896596074104309, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0280037727206945419, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0638669133186340332, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(0.13651759922504425, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0657804235816001892, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0629896596074104309, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0280037727206945419, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[25], self.epsilon);

  // self.playAudio = YES;
  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testRolandPianoChordRenderCubic4thOrder {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::cubic4thOrder}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  int cycles = 5;
  AVAudioFrameCount noteOnIndex = 1;
  AVAudioFrameCount chordDuration = 30;
  AVAudioFrameCount noteOffIndex = AVAudioFrameCount(noteOnIndex + chordDuration * 0.75);

  auto mixer{harness.createMixer(12)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  auto playChord = [&](uint8_t note1, uint8_t note2, uint8_t note3, bool sustain) {
    harness.renderUntil(mixer, noteOnIndex);
    harness.sendNoteOn(note1);
    harness.sendNoteOn(note2);
    harness.sendNoteOn(note3);
    harness.renderUntil(mixer, noteOffIndex);
    if (!sustain) {
      harness.sendNoteOff(note1);
      harness.sendNoteOff(note2);
      harness.sendNoteOff(note3);
    }
    noteOnIndex += chordDuration;
    noteOffIndex += chordDuration;
  };

  for (auto count = 0; count < cycles; ++count) {
    playChord(60, 64, 67, false);
    samples.push_back(harness.lastDrySample());
    playChord(60, 65, 69, false);
    samples.push_back(harness.lastDrySample());
    playChord(60, 64, 67, false);
    samples.push_back(harness.lastDrySample());
    playChord(59, 62, 67, false);
    samples.push_back(harness.lastDrySample());
    playChord(60, 64, 67, count == cycles - 1);
    samples.push_back(harness.lastDrySample());
  }

  XCTAssertEqual(size_t(32), engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0584149733185768127, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.139659687876701355, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0654851198196411133, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0635829642415046692, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0277795381844043732, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0636894926428794861, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.136539652943611145, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0655902549624443054, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0635517537593841553, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0277947913855314255, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0636894926428794861, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.136539652943611145, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0655902549624443054, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0635517537593841553, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0277947913855314255, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0636894926428794861, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.136539652943611145, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0655902549624443054, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0635517537593841553, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0277947913855314255, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0636894926428794861, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(0.136539652943611145, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0655902549624443054, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0635517537593841553, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0277947913855314255, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[25], self.epsilon);

  // self.playAudio = YES;
  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIProgramChange {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  NSString* name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
  NSLog(@"name: |%@|", name);
  XCTAssertTrue([name isEqualToString:@"Piano 1"]);

  int seconds = 1;
  auto mixer{harness.createMixer(seconds)};
  std::vector<AUValue> samples;

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.renderUntil(mixer, AVAudioFrameCount(AVAudioFrameCount(harness.renders() * 0.5)));
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::programChange);
  midiEvent.data[1] = 23;
  midiEvent.length = 2;

  engine.doMIDIEvent(midiEvent);
  name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
  NSLog(@"name: |%@|", name);
  XCTAssertTrue([name isEqualToString:@"Bandoneon"]);
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00312164006755, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0106693943962, samples[1], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testYamahaPianoChordRender {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 3;
  AVAudioFrameCount noteOnIndex = 1;
  AVAudioFrameCount chordDuration = 30;
  AVAudioFrameCount noteOffIndex = AVAudioFrameCount(noteOnIndex + chordDuration * .75);

  auto mixer{harness.createMixer(seconds)};

  // Set NPRN state so that voices send 20% output to the chorus channel
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnMSB, 120);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Index::chorusEffectSend));
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 65);

  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  auto playChord = [&](uint8_t note1, uint8_t note2, uint8_t note3, bool sustain) {
    harness.renderUntil(mixer, noteOnIndex);
    harness.sendNoteOn(note1);
    harness.sendNoteOn(note2);
    harness.sendNoteOn(note3);
    harness.renderUntil(mixer, noteOffIndex);
    if (!sustain) {
      harness.sendNoteOff(note1);
      harness.sendNoteOff(note2);
      harness.sendNoteOff(note3);
    }
    noteOnIndex += chordDuration;
    noteOffIndex += chordDuration;
  };

  playChord(60, 64, 67, false);
  playChord(60, 65, 69, false);
  playChord(60, 64, 67, false);
  playChord(59, 62, 67, false);
  playChord(60, 64, 67, true);

  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(3), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.duration()];
  [self playSamples: harness.chorusBuffer() count: harness.duration()];
}

- (void)testEngineMIDINoteOnOffProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  // Note 1 on
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  // Note 2 on
  midiEvent.data[1] = 0x44;
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());

  // Render 20% of total
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));

  // Note 1 off
  midiEvent.data[0] = 0x80;
  midiEvent.data[1] = 0x40;
  midiEvent.length = 2;
  engine.doMIDIEvent(midiEvent);

  // Render another 20%
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.4));

  // Note 2 off
  midiEvent.data[1] = 0x44;
  engine.doMIDIEvent(midiEvent);

  // Render rest
  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIPitchBendProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x64;
  midiEvent.length = 3;

  // Note 1 on
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());

  // Note 2 on
  midiEvent.data[1] = 0x44;
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(4), engine.activeVoiceCount());

  // Note 3 on
  midiEvent.data[1] = 0x47;
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(6), engine.activeVoiceCount());

  // Render 20% of total
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));
  samples.push_back(harness.lastDrySample());

  // Pitch wheel all the way up
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::pitchBend);
  midiEvent.data[1] = 127;
  midiEvent.data[2] = 127;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.4));
  samples.push_back(harness.lastDrySample());

  // Pitch wheel all the way down
  midiEvent.data[1] = 0;
  midiEvent.data[2] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.6));
  samples.push_back(harness.lastDrySample());

  // Pitch wheel at center
  midiEvent.data[1] = 0;
  midiEvent.data[2] = 0x20;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.8));
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.118135415018, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0529967471957, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0434629619122, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.024333762005, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00972236786038, samples[4], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineExcludeClassNoteTermination
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context1.path(), 260);

  auto seconds = 1.5;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  harness.sendNoteOn(46);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendNoteOn(46);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.4));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendNoteOn(46);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.6));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendNoteOn(46);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.8));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendNoteOn(46);
  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIChannelPressure
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context1.path(), 14);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
  harness.sendNoteOn(67);
  harness.sendNoteOn(72);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));
  samples.push_back(harness.lastDrySample());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::channelPressure);
  midiEvent.length = 2;

  midiEvent.data[1] = 127;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.6));
  samples.push_back(harness.lastDrySample());

  midiEvent.data[1] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0138967316598, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00947172474116, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00546989124268, samples[2], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIKeyPressure // no effect as there is no modulator using it
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context1.path(), 14);

  auto seconds = 2.0;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60, 127);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.1));
  samples.push_back(harness.lastDrySample());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::keyPressure);
  midiEvent.data[1] = 60;
  midiEvent.length = 3;

  for (auto count = 1; count <= 4; ++count) {
    midiEvent.data[2] = 127;
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * (0.1 + 0.2 * count)));
    samples.push_back(harness.lastDrySample());

    midiEvent.data[2] = 32;
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * (0.2 + 0.2 * count)));
    samples.push_back(harness.lastDrySample());
  }

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.00668354937807, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0404301397502, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0571423061192, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00673362473026, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0436884015799, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.023754844442, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000322586420225, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0209613889456, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0113112898543, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0113112898543, samples[9], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineSustainPedalProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context1.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(72, 127);
  harness.sendNoteOn(76, 127);
  harness.sendNoteOn(79, 127);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.1));
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sustainPedalActive);

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = SF2::valueOf(MIDI::ControlChange::sustainSwitch);
  midiEvent.data[2] = 64;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertTrue(engine.channelState().pedalState().sustainPedalActive);

  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.4));
  XCTAssertTrue(engine.channelState().pedalState().sustainPedalActive);
  XCTAssertEqual(size_t(3), engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  midiEvent.data[2] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.5));
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sustainPedalActive);

  harness.sendNoteOn(72, 127);
  harness.sendNoteOn(76, 127);
  harness.sendNoteOn(79, 127);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.7));
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.9));
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0495313704014, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0211332235485, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0019038640894, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00263028102927, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0211724154651, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000254703074461, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(7.80675327405e-05, samples[6], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineSostenutoPedalProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context1.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(72, 127);
  harness.sendNoteOn(76, 127);
  harness.sendNoteOn(79, 127);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.1));
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sostenutoPedalActive);

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = SF2::valueOf(MIDI::ControlChange::sostenutoSwitch);
  midiEvent.data[2] = 64;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertTrue(engine.channelState().pedalState().sostenutoPedalActive);

  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.5));
  XCTAssertTrue(engine.channelState().pedalState().sostenutoPedalActive);
  XCTAssertEqual(size_t(3), engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOn(74, 127);
  harness.sendNoteOn(78, 127);
  harness.sendNoteOn(81, 127);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.7));
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(6), engine.activeVoiceCount());

  harness.sendNoteOff(74);
  harness.sendNoteOff(88);
  harness.sendNoteOff(81);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.9));
  XCTAssertEqual(size_t(6), engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(6), engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0495313704014, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0211332235485, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0149366548285, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0159172601998, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00340272067115, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00402484135702, samples[5], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIControlChangeCC10ForPanning
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 18);

  int seconds = 4;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
  harness.sendNoteOn(64);
  harness.sendNoteOn(67);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = 10;
  midiEvent.length = 3;

  // Pan left
  auto steps = int(AVAudioFrameCount(harness.renders() * 0.2));
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = uint8_t(64 - (step / steps * 64));
    engine.doMIDIEvent(midiEvent);
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = uint8_t(64 - (step / steps * 64));
    engine.doMIDIEvent(midiEvent);
    harness.renderOnce(mixer);
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = uint8_t(64 + (step / steps * 63));
    engine.doMIDIEvent(midiEvent);
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = uint8_t(64 + (step / steps * 63));
    engine.doMIDIEvent(midiEvent);
    harness.renderOnce(mixer);
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00463884416967630386, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00463884416967630386, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000323427491821348667, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000315399491228163242, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00013238412793725729, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000125891529023647308, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00489116832613945007, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0045499289408326149, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000839568732772022486, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000761541479732841253, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00401247292757034302, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00354868778958916664, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00236437702551484108, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00203871633857488632, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00601302320137619972, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00518481060862541199, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00125735113397240639, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00105691398493945599, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.002091564005240798, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00171375484205782413, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00807644892483949661, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00647045578807592392, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00138890743255615234, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00108435284346342087, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00160303444135934114, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0012194173177704215, samples[25], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00266135856509208679, samples[26], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00197217869572341442, samples[27], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00231874198652803898, samples[28], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00171828526072204113, samples[29], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00342545518651604652, samples[30], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00247233454138040543, samples[31], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00430048536509275436, samples[32], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00303253484889864922, samples[33], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0015354156494140625, samples[34], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00105407857336103916, samples[35], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0048499545082449913, samples[36], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00324063585139811039, samples[37], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000999168958514928818, samples[38], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000649611989501863718, samples[39], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00150331982877105474, samples[40], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000950726796872913837, samples[41], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00386417284607887268, samples[42], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00244377274066209793, samples[43], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000869361450895667076, samples[44], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000536509323865175247, samples[45], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00456920824944972992, samples[46], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00274111749604344368, samples[47], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00693331612274050713, samples[48], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00404176861047744751, samples[49], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00076151976827532053, samples[50], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000431198219303041697, samples[51], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000495558429975062609, samples[52], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000272435630904510617, samples[53], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00231201830320060253, samples[54], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00123346596956253052, samples[55], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00199842266738414764, samples[56], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00106616225093603134, samples[57], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00514498632401227951, samples[58], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00267260614782571793, samples[59], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000393079273635521531, samples[60], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000197956222109496593, samples[61], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00105498253833502531, samples[62], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00051477731904014945, samples[63], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000906208646483719349, samples[64], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00042816929635591805, samples[65], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0049454541876912117, samples[66], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0022610742598772049, samples[67], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00265549309551715851, samples[68], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00117897125892341137, samples[69], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00216935621574521065, samples[70], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0009631388820707798, samples[71], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00782275479286909103, samples[72], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00335606979206204414, samples[73], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00225426489487290382, samples[74], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000933747098315507174, samples[75], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00159314193297177553, samples[76], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000636566255707293749, samples[77], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00224273931235074997, samples[78], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000863602675963193178, samples[79], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000559184933081269264, samples[80], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000208292331080883741, samples[81], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00025432585971429944, samples[82], self.epsilon);
  XCTAssertEqualWithAccuracy(-9.47345542954280972e-05, samples[83], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00208889273926615715, samples[84], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000748343183659017086, samples[85], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0097654322162270546, samples[86], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00336060160771012306, samples[87], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00147857714910060167, samples[88], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000488133926410228014, samples[89], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00117124151438474655, samples[90], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000370415044017136097, samples[91], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000706437451299279928, samples[92], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000213689680094830692, samples[93], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00269276788458228111, samples[94], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000782321440055966377, samples[95], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00019445689395070076, samples[96], self.epsilon);
  XCTAssertEqualWithAccuracy(5.64949004910886288e-05, samples[97], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00673857051879167557, samples[98], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00186623819172382355, samples[99], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00250842282548546791, samples[100], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000660880818031728268, samples[101], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00295163551345467567, samples[102], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000738114526029676199, samples[103], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000722523080185055733, samples[104], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000171063555171713233, samples[105], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0046644182875752449, samples[106], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00105031649582087994, samples[107], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00164589821361005306, samples[108], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000348945788573473692, samples[109], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0052247992716729641, samples[110], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00110770633909851313, samples[111], self.epsilon);
  XCTAssertEqualWithAccuracy(1.28321116790175438e-05, samples[112], self.epsilon);
  XCTAssertEqualWithAccuracy(2.55246413871645927e-06, samples[113], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0097249327227473259, samples[114], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00180767732672393322, samples[115], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00251405267044901848, samples[116], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000434704183135181665, samples[117], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00318716932088136673, samples[118], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000515067134983837605, samples[119], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000756415945943444967, samples[120], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000112507288577035069, samples[121], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00148017588071525097, samples[122], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000201180024305358529, samples[123], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000117528601549565792, samples[124], self.epsilon);
  XCTAssertEqualWithAccuracy(-1.59740447998046875e-05, samples[125], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00669689476490020752, samples[126], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000824648246634751558, samples[127], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000363105442374944687, samples[128], self.epsilon);
  XCTAssertEqualWithAccuracy(4.00872086174786091e-05, samples[129], self.epsilon);
  XCTAssertEqualWithAccuracy(9.84219368547201157e-05, samples[130], self.epsilon);
  XCTAssertEqualWithAccuracy(9.61566547630354762e-06, samples[131], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00634309789165854454, samples[132], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000549371819943189621, samples[133], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000576613703742623329, samples[134], self.epsilon);
  XCTAssertEqualWithAccuracy(4.26474143750965595e-05, samples[135], self.epsilon);
  XCTAssertEqualWithAccuracy(8.41704895719885826e-05, samples[136], self.epsilon);
  XCTAssertEqualWithAccuracy(5.16283762408420444e-06, samples[137], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00844179932028055191, samples[138], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000517801439855247736, samples[139], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00320952758193016052, samples[140], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000156410591444000602, samples[141], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0065908040851354599, samples[142], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000238218315644189715, samples[143], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000770035898312926292, samples[144], self.epsilon);
  XCTAssertEqualWithAccuracy(-1.93571904674172401e-05, samples[145], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00152004370465874672, samples[146], self.epsilon);
  XCTAssertEqualWithAccuracy(-1.91024373634718359e-05, samples[147], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00130360154435038567, samples[148], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[149], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00521253235638141632, samples[150], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00381309306249022484, samples[152], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00381309306249022484, samples[153], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000672512280289083719, samples[154], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000689630280248820782, samples[155], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00204816996119916439, samples[156], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00215379893779754639, samples[157], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00415353616699576378, samples[158], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00446504633873701096, samples[159], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00311541720293462276, samples[160], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00343462149612605572, samples[161], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00344886910170316696, samples[162], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00389960873872041702, samples[163], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00290588196367025375, samples[164], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00328565714880824089, samples[165], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00187054113484919071, samples[166], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00216933805495500565, samples[167], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000841193716041743755, samples[168], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00100072077475488186, samples[169], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000935700605623424053, samples[170], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00114198215305805206, samples[171], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00104256486520171165, samples[172], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00130133354105055332, samples[173], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00467048631981015205, samples[174], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00598225323483347893, samples[175], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00148889375850558281, samples[176], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00190706877037882805, samples[177], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00174367881845682859, samples[178], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00229222350753843784, samples[179], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00370319793000817299, samples[180], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00499728415161371231, samples[181], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00198810896836221218, samples[182], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0027545541524887085, samples[183], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00030683854129165411, samples[184], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000435132533311843872, samples[185], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00376139464788138866, samples[186], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00547900702804327011, samples[187], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000249442586209625006, samples[188], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000363348692189902067, samples[189], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000919440703000873327, samples[190], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00137604027986526489, samples[191], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0023380722850561142, samples[192], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00359619176015257835, samples[193], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00151033909060060978, samples[194], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00238819723017513752, samples[195], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00154040136840194464, samples[196], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00249607069417834282, samples[197], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00135981745552271605, samples[198], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00226669944822788239, samples[199], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0020596296526491642, samples[200], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00353312212973833084, samples[201], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000741779862437397242, samples[202], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00127246114425361156, samples[203], self.epsilon);
  XCTAssertEqualWithAccuracy(5.71506097912788391e-06, samples[204], self.epsilon);
  XCTAssertEqualWithAccuracy(1.00932084023952484e-05, samples[205], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00321692181751132011, samples[206], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0058515593409538269, samples[207], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00267160474322736263, samples[208], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00500767771154642105, samples[209], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00112783140502870083, samples[210], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00217116787098348141, samples[211], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00129855470731854439, samples[212], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00257852440699934959, samples[213], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000178143149241805077, samples[214], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000353736802935600281, samples[215], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00195842538960278034, samples[216], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00401358865201473236, samples[217], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00200803414918482304, samples[218], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00424994854256510735, samples[219], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000881390413269400597, samples[220], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00192778976634144783, samples[221], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00170125113800168037, samples[222], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00383186736144125462, samples[223], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0014559449627995491, samples[224], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00339370197616517544, samples[225], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00272418931126594543, samples[226], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00634988769888877869, samples[227], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000174786197021603584, samples[228], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000421971199102699757, samples[229], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00275337742641568184, samples[230], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00689090974628925323, samples[231], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000117601040983572602, samples[232], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000305404653772711754, samples[233], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0017227918142452836, samples[234], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00462503405287861824, samples[235], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000726698432117700577, samples[236], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00202847435139119625, samples[237], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000566473521757870913, samples[238], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00158122950233519077, samples[239], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000202455295948311687, samples[240], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000588306458666920662, samples[241], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00176682998426258564, samples[242], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00535179814323782921, samples[243], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00114973739255219698, samples[244], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00363543583080172539, samples[245], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00148053024895489216, samples[246], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00489448942244052887, samples[247], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00114825251512229443, samples[248], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00395231088623404503, samples[249], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00024743290850892663, samples[250], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000893425021786242723, samples[251], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000596914440393447876, samples[252], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00215532537549734116, samples[253], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000265140668489038944, samples[254], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00100636156275868416, samples[255], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00212830468080937862, samples[256], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00851084664463996887, samples[257], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0013959535863250494, samples[258], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00589610543102025986, samples[259], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000647424953058362007, samples[260], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00287519046105444431, samples[261], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00014286572695709765, samples[262], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000673864968121051788, samples[263], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00082644785288721323, samples[264], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00389816658571362495, samples[265], self.epsilon);
  XCTAssertEqualWithAccuracy(-7.5228686910122633e-05, samples[266], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000378199853003025055, samples[267], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00054623984033241868, samples[268], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0029386584646999836, samples[269], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00109195581171661615, samples[270], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00631517870351672173, samples[271], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00112237234134227037, samples[272], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00694509595632553101, samples[273], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000587885268032550812, samples[274], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00395250599831342697, samples[275], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00060696830041706562, samples[276], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00408080639317631721, samples[277], self.epsilon);
  XCTAssertEqualWithAccuracy(2.66738788923248649e-05, samples[278], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000196252367459237576, samples[279], self.epsilon);
  XCTAssertEqualWithAccuracy(4.40241419710218906e-05, samples[280], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000357516342774033546, samples[281], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000220397021621465683, samples[282], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00199633138254284859, samples[283], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000674972543492913246, samples[284], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00690873386338353157, samples[285], self.epsilon);
  XCTAssertEqualWithAccuracy(4.77963476441800594e-05, samples[286], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000551860779523849487, samples[287], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000179758237209171057, samples[288], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00207550544291734695, samples[289], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000125498336274176836, samples[290], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00169679848477244377, samples[291], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000461929797893390059, samples[292], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00753091415390372276, samples[293], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000132711778860539198, samples[294], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0027232305146753788, samples[295], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000187522164196707308, samples[296], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00518819037824869156, samples[297], self.epsilon);
  XCTAssertEqualWithAccuracy(2.45692026510369033e-05, samples[298], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000977371702902019024, samples[299], self.epsilon);
  XCTAssertEqualWithAccuracy(9.85923179541714489e-05, samples[300], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00784531421959400177, samples[301], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIReset {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  harness.sendNoteOn(64);
  harness.sendNoteOn(67);
  XCTAssertEqual(size_t(3), engine.activeVoiceCount());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::reset);
  midiEvent.length = 1;
  engine.doMIDIEvent(midiEvent);

  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineMIDILoad {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());

  const NSURL* url = self.contexts->context0.url();
  NSLog(@"URL: %@", url);
  const NSString* path = [url path];
  NSLog(@"path: %@", path);
  std::string tmp([path cStringUsingEncoding: NSUTF8StringEncoding],
                  [path lengthOfBytesUsingEncoding: NSUTF8StringEncoding]);
  auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
  overrides.emplace_back(123, 456);
  auto payload = engine.createLoadFileUsePresetPayload(tmp, 234, overrides);
  harness.sendRaw(payload);
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual(std::string("SFX"), engine.activePresetName());
}

- (void)testEngineOneVoicePerKey
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 1;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 0.0);
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.25));
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.5));
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());

  harness.sendAllOff();
  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 1.0);
  XCTAssertTrue(engine.oneVoicePerKeyModeEnabled());

  harness.sendNoteOn(60);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.75));
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.00513585424051, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0024097810965, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00612613232806, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000495888874866, samples[3], self.epsilon);

  XCTAssertNotEqualWithAccuracy(samples[1], samples[3], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineActiveVoiceCount
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto address = valueOf(ParameterAddress::activeVoiceCount);
  AUParameter* param = [engine.parameterTree() parameterWithAddress: address];
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.sendNoteOn(72);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.1));
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());
  XCTAssertEqual(2, param.value);

  harness.sendNoteOff(60);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.5));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  XCTAssertEqual(1, param.value);

  harness.sendNoteOff(72);
  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
  XCTAssertEqual(0, param.value);

  // Should be harmless
  param.value = 99;
  XCTAssertEqual(0, param.value);
}

- (void)testEngineParameterTreeHasGenerators
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto flags = kAudioUnitParameterFlag_IsReadable | kAudioUnitParameterFlag_IsWritable;

  for (auto index: IndexIterator()) {
    const auto& definition = Definition::definition(index);
    if (definition.valueKind() == Definition::ValueKind::UNUSED) {
      continue;
    }

    auto address = AUParameterAddress(valueOf(index));
    AUParameter* param = [engine.parameterTree() parameterWithAddress: address];
    XCTAssertNotNil(param);
    XCTAssertEqual(flags, [param flags]);
  }
}

- (void)testEngineParameterControlChangeForPanning
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};

  harness.load(self.contexts->context0.path(), 18);

  int seconds = 4;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
  harness.sendNoteOn(64);
  harness.sendNoteOn(67);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  // Pan left
  auto steps = int(AVAudioFrameCount(harness.renders() * 0.2));
  for (auto step = 1_F; step <= steps; ++step) {
    harness.setParameter(Index::pan, AUValue(step / steps * -500_F));
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    harness.setParameter(Index::pan, AUValue(step / steps * -500_F));
    harness.renderOnce(mixer);
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    harness.setParameter(Index::pan, AUValue(step / steps * 500_F));
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    harness.setParameter(Index::pan, AUValue(step / steps * 500_F));
    harness.renderOnce(mixer);
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00463884416968, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00463884416968, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000322931911796, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000315907062031, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000131789478473, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000126514001749, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00486967293546, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00457292748615, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000834767357446, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000766801647842, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00397884938866, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00358634628356, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00234181783162, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00206459010951, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00601302320138, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00518481060863, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00125402456615, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00106085883453, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0020834649913, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00172359205317, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00804586801678, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00650844257325, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00138034834526, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00109522778075, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00159147079103, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00123447121587, samples[25], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00263951299712, samples[26], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00200132187456, samples[27], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00231603998691, samples[28], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00172192545142, samples[29], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00341767095961, samples[30], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00248308340088, samples[31], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00429093744606, samples[32], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00304603017867, samples[33], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00152876228094, samples[34], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00106370507274, samples[35], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00482435338199, samples[36], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00327862706035, samples[37], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000993002206087, samples[38], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000658999895677, samples[39], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0014912544284, samples[40], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000969542423263, samples[41], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00386032951064, samples[42], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00244983960874, samples[43], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000868517439812, samples[44], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000537874293514, samples[45], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00455624051392, samples[46], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00276261894032, samples[47], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00690778438002, samples[48], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00408525206149, samples[49], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000758109963499, samples[50], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000437165785115, samples[51], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000492533086799, samples[52], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000277867948171, samples[53], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0022963359952, samples[54], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0012624214869, samples[55], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00199674535543, samples[56], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00106930010952, samples[57], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00513656483963, samples[58], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00268875644542, samples[59], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000392142101191, samples[60], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00019980633806, samples[61], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00105172721669, samples[62], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000521395762917, samples[63], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000902132829651, samples[64], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00043669086881, samples[65], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00492029357702, samples[66], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00231531448662, samples[67], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00264236959629, samples[68], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00120809813961, samples[69], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00216784095392, samples[70], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000966545310803, samples[71], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00781217310578, samples[72], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00338062923402, samples[73], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00224983971566, samples[74], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000944359693676, samples[75], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00158809334971, samples[76], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000649059074931, samples[77], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00223450060003, samples[78], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000884701381437, samples[79], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000557197025046, samples[80], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000213553197682, samples[81], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000254325859714, samples[82], self.epsilon);
  XCTAssertEqualWithAccuracy(-9.47345542954e-05, samples[83], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00208771461621, samples[84], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00075162347639, samples[85], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00975482631475, samples[86], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0033912640065, samples[87], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00147548108362, samples[88], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000497414439451, samples[89], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00116829620674, samples[90], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0003796024248, samples[91], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000704392092302, samples[92], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000220338130021, samples[93], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00268400320783, samples[94], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000811882084236, samples[95], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000194456893951, samples[96], self.epsilon);
  XCTAssertEqualWithAccuracy(5.64949004911e-05, samples[97], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00673563033342, samples[98], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00187682069372, samples[99], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00250528077595, samples[100], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000672694179229, samples[101], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0029469395522, samples[102], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00075664545875, samples[103], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000721157295629, samples[104], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000176732894033, samples[105], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00465431204066, samples[106], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00109423045069, samples[107], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00164196221158, samples[108], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000367022003047, samples[109], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00522479927167, samples[110], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0011077063391, samples[111], self.epsilon);
  XCTAssertEqualWithAccuracy(1.28239626065e-05, samples[112], self.epsilon);
  XCTAssertEqualWithAccuracy(2.5927729439e-06, samples[113], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00971630681306, samples[114], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00185348466039, samples[115], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00251127150841, samples[116], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000450491672382, samples[117], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00318302563392, samples[118], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000540082924999, samples[119], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000755321816541, samples[120], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000119631222333, samples[121], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00147787481546, samples[122], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000217442895519, samples[123], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000117503339424729347, samples[124], self.epsilon);
  XCTAssertEqualWithAccuracy(-1.61586503963917494e-05, samples[125], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00669427076354622841, samples[126], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000845683040097355843, samples[127], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000362912658601999283, samples[128], self.epsilon);
  XCTAssertEqualWithAccuracy(4.1797844460234046e-05, samples[129], self.epsilon);
  XCTAssertEqualWithAccuracy(9.83430654741823673e-05, samples[130], self.epsilon);
  XCTAssertEqualWithAccuracy(1.03883430710993707e-05, samples[131], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00633858796209096909, samples[132], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000599172897636890411, samples[133], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000576186459511518478, samples[134], self.epsilon);
  XCTAssertEqualWithAccuracy(4.80798771604895592e-05, samples[135], self.epsilon);
  XCTAssertEqualWithAccuracy(8.40992433950304985e-05, samples[136], self.epsilon);
  XCTAssertEqualWithAccuracy(6.2201288528740406e-06, samples[137], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00844097509980201721, samples[138], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000531061086803674698, samples[139], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00320902070961892605, samples[140], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000166492827702313662, samples[141], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00658917753025889397, samples[142], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000279624597169458866, samples[143], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000769898993894457817, samples[144], self.epsilon);
  XCTAssertEqualWithAccuracy(-2.4195054720621556e-05, samples[145], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00151984672993421555, samples[146], self.epsilon);
  XCTAssertEqualWithAccuracy(-3.10401192109566182e-05, samples[147], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00130352284759283066, samples[148], self.epsilon);
  XCTAssertEqualWithAccuracy(-1.43335573739022948e-05, samples[149], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00521253235638141632, samples[150], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0037709362804889679, samples[152], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00385478883981704712, samples[153], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000667075335513800383, samples[154], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000694890972226858139, samples[155], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00203459663316607475, samples[156], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00216662557795643806, samples[157], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00412539951503276825, samples[158], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00449105584993958473, samples[159], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00310461153276264668, samples[160], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0034443920012563467, samples[161], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00344273960217833519, samples[162], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00390502135269343853, samples[163], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00286436476744711399, samples[164], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00332191330380737782, samples[165], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00185001303907483816, samples[166], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00218687090091407299, samples[167], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000833308207802474499, samples[168], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0010072966106235981, samples[169], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000928506720811128616, samples[170], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00114783889148384333, samples[171], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00103642081376165152, samples[172], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00130623194854706526, samples[173], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00465166987851262093, samples[174], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0059968968853354454, samples[175], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00146178517024964094, samples[176], self.epsilon);
  XCTAssertEqualWithAccuracy(0.001927926205098629, samples[177], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00171836954541504383, samples[178], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00231125764548778534, samples[179], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00365593563765287399, samples[180], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00503196381032466888, samples[181], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00196641357615590096, samples[182], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00277008349075913429, samples[183], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000304098590277135372, samples[184], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000437051989138126373, samples[185], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00373553391546010971, samples[186], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00549667142331600189, samples[187], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000243704591412097216, samples[188], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000367221946362406015, samples[189], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000902076775673776865, samples[190], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00138748530298471451, samples[191], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00229838932864367962, samples[192], self.epsilon);
  XCTAssertEqualWithAccuracy(0.003621682059019804, samples[193], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00148776406422257423, samples[194], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00240232539363205433, samples[195], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00152074988000094891, samples[196], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00250809197314083576, samples[197], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0013455486623570323, samples[198], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00227519846521317959, samples[199], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00204295758157968521, samples[200], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0035427887924015522, samples[201], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000723717384971678257, samples[202], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00128282047808170319, samples[203], self.epsilon);
  XCTAssertEqualWithAccuracy(5.58793544769287109e-06, samples[204], self.epsilon);
  XCTAssertEqualWithAccuracy(1.01642217487096786e-05, samples[205], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00315238768234848976, samples[206], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0058865770697593689, samples[207], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00263219280168414116, samples[208], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0050285053439438343, samples[209], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00111074442975223064, samples[210], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00217995885759592056, samples[211], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00128232792485505342, samples[212], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0025866327341645956, samples[213], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000172564992681145668, samples[214], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000356491189450025558, samples[215], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00190149073023349047, samples[216], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00404087360948324203, samples[217], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00195447076112031937, samples[218], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00427484605461359024, samples[219], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000863182649482041597, samples[220], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00193601124919950962, samples[221], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00166506180539727211, samples[222], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00384773104451596737, samples[223], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00142924627289175987, samples[224], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00340503198094666004, samples[225], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00261406996287405491, samples[226], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0063960077241063118, samples[227], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000168136670254170895, samples[228], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000424664700403809547, samples[229], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00265568774193525314, samples[230], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0069291447289288044, samples[231], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000114235823275521398, samples[232], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00030667940154671669, samples[233], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00167183368466794491, samples[234], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00464369729161262512, samples[235], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000707548519130796194, samples[236], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00203523319214582443, samples[237], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000536569161340594292, samples[238], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00159162585623562336, samples[239], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000192260427866131067, samples[240], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00059171655448153615, samples[241], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0016825494822114706, samples[242], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00537889031693339348, samples[243], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00110396358650177717, samples[244], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00364959659054875374, samples[245], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00142662413418292999, samples[246], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00491047278046607971, samples[247], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0011047261068597436, samples[248], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0039646979421377182, samples[249], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000240408451645635068, samples[250], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00089534104336053133, samples[251], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000556183920707553625, samples[252], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00216619321145117283, samples[253], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000247713411226868629, samples[254], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00101079279556870461, samples[255], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00200777663849294186, samples[256], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00854008365422487259, samples[257], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00132175267208367586, samples[258], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00591318169608712196, samples[259], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000611244060564786196, samples[260], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0028830990195274353, samples[261], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000136508402647450566, samples[262], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000675181625410914421, samples[263], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000746679084841161966, samples[264], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00391422910615801811, samples[265], self.epsilon);
  XCTAssertEqualWithAccuracy(-6.8086839746683836e-05, samples[266], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00037955096922814846, samples[267], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000500013935379683971, samples[268], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00294687598943710327, samples[269], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00100257107987999916, samples[270], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0063299844041466713, samples[271], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00102407950907945633, samples[272], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00696026813238859177, samples[273], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000544390524737536907, samples[274], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00395873095840215683, samples[275], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000517087173648178577, samples[276], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00409316644072532654, samples[277], self.epsilon);
  XCTAssertEqualWithAccuracy(2.26610718527808785e-05, samples[278], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000196755980141460896, samples[279], self.epsilon);
  XCTAssertEqualWithAccuracy(3.78404802177101374e-05, samples[280], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000358223915100097656, samples[281], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000189012818736955523, samples[282], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00199954700656235218, samples[283], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000577238446567207575, samples[284], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00691758515313267708, samples[285], self.epsilon);
  XCTAssertEqualWithAccuracy(4.08578198403120041e-05, samples[286], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000552417943254113197, samples[287], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000130809901747852564, samples[288], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00207916437648236752, samples[289], self.epsilon);
  XCTAssertEqualWithAccuracy(8.81564701558090746e-05, samples[290], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00169914751313626766, samples[291], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000319901737384498119, samples[292], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00753828324377536774, samples[293], self.epsilon);
  XCTAssertEqualWithAccuracy(-8.56402548379264772e-05, samples[294], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00272511690855026245, samples[295], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000106006482383236289, samples[296], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00519049586728215218, samples[297], self.epsilon);
  XCTAssertEqualWithAccuracy(1.07499417936196551e-05, samples[298], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000977621413767337799, samples[299], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[300], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00784593448042869568, samples[301], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineChangePresetByIndex
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
  harness.load(self.contexts->context0.path(), 0);
  XCTAssertEqual("Piano 1", engine.activePresetName());
  auto payload = engine.createLoadFileUsePresetPayload("", 1, overrides);
  harness.sendRaw(payload);
  XCTAssertEqual("Piano 2", engine.activePresetName());
  harness.sendRaw(engine.createLoadFileUsePresetPayload("", 128, overrides));
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("SynthBass101", engine.activePresetName());
  harness.sendRaw(engine.createLoadFileUsePresetPayload("", engine.presetCount() - 1, overrides));
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("SFX", engine.activePresetName());
}

- (void)testEngineChangePresetByBankProgram
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);
  XCTAssertEqual("Piano 1", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgramPayload(0, 1));
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 2", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgramPayload(1, 38));
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("SynthBass101", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgramPayload(128, 56));
  std::clog << engine.activePresetName() << '\n';
 }

- (void)testEngineAllSoundOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::allSoundOff, 0));
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineAllNotesOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::allNotesOff, 0));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
}

- (void)testEngineResetAllControllers
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  XCTAssertEqual(0, engine.channelState().continuousControllerValue(MIDI::ControlChange::bankSelectLSB));
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::bankSelectLSB, 123u);
  XCTAssertEqual(123u, engine.channelState().continuousControllerValue(MIDI::ControlChange::bankSelectLSB));

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::resetAllControllers, 0));
  XCTAssertEqual(0, engine.channelState().continuousControllerValue(MIDI::ControlChange::bankSelectLSB));
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineMonoOn
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  XCTAssertFalse(engine.monophonicModeEnabled());

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::monoOn, 0));
  XCTAssertTrue(engine.monophonicModeEnabled());
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEnginePolyOn
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::monoOn, 0));
  XCTAssertTrue(engine.monophonicModeEnabled());

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::polyOn, 0));
  XCTAssertFalse(engine.monophonicModeEnabled());
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineOmniOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::omniOff, 0));
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineOmniOn
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::omniOn, 0));
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

@end
