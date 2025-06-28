// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <iostream>
#include <vector>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.hpp"
#include "SF2Lib/Utils/Base64.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"

using namespace SF2;
using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

@interface EngineTests : SamplePlayingTestCase
@end

@implementation EngineTests

- (void)setUp {
  [super setUp];
  // self.playAudio = YES;
}

- (void)testInit {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertEqual(engine.voiceCount(), 32);
  XCTAssertEqual(engine.activeVoiceCount(), 0);
  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
  XCTAssertFalse(engine.portamentoModeEnabled());
  XCTAssertEqual(100, engine.portamentoRate());
  XCTAssertTrue(engine.retriggerModeEnabled());
}

- (void)testPortamento {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};

  XCTAssertFalse(engine.portamentoModeEnabled());
  harness.setParameter(Parameters::EngineParameterAddress::portamentoModeEnabled, 1.0);
  XCTAssertTrue(engine.portamentoModeEnabled());

  harness.setParameter(Parameters::EngineParameterAddress::portamentoRate, 12345);
  XCTAssertEqual(12345, engine.portamentoRate());

  harness.setParameter(Parameters::EngineParameterAddress::portamentoRate, 987);
  XCTAssertEqual(987, engine.portamentoRate());

  harness.setParameter(Parameters::EngineParameterAddress::portamentoModeEnabled, 0.0);
  XCTAssertFalse(engine.portamentoModeEnabled());
}

- (void)testPhonicMode {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};

  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.monophonicModeEnabled());

  harness.setParameter(Parameters::EngineParameterAddress::polyphonicModeEnabled, 0.0);
  XCTAssertFalse(engine.polyphonicModeEnabled());
  XCTAssertTrue(engine.monophonicModeEnabled());

  harness.setParameter(Parameters::EngineParameterAddress::polyphonicModeEnabled, 1.0);
  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.monophonicModeEnabled());
}

- (void)testOneVoicePerKey {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};

  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());

  harness.setParameter(Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled, 1.0);
  XCTAssertTrue(engine.oneVoicePerKeyModeEnabled());

  harness.setParameter(Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled, 0.0);
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
}

- (void)testRetriggering {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};

  XCTAssertTrue(engine.retriggerModeEnabled());

  harness.setParameter(Parameters::EngineParameterAddress::retriggerModeEnabled, 0.0);
  XCTAssertFalse(engine.retriggerModeEnabled());

  harness.setParameter(Parameters::EngineParameterAddress::retriggerModeEnabled, 1.0);
  XCTAssertTrue(engine.retriggerModeEnabled());
}

- (void)testLoad {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};
  XCTAssertFalse(engine.hasActivePreset());

  harness.load(contexts.context0.path(), 0);

  XCTAssertEqual(harness.load(contexts.context0.path(), 0), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqual(engine.presetCount(), 235);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual(harness.load(contexts.context1.path(), 10000), SF2::IO::File::LoadResponse::ok);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual(harness.load(contexts.context2.path(), 0), SF2::IO::File::LoadResponse::ok);
}

- (void)testUsePresetByIndex {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

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
  XCTAssertEqual(harness.load(contexts.context0.path(), 0), SF2::IO::File::LoadResponse::ok);

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
  harness.usePresetWithBankProgram(-1, -1);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  harness.usePresetWithBankProgram(-1, 0);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  harness.usePresetWithBankProgram(0, -1);
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
  harness.load(contexts.context2.path(), 0);

  int cycles = 5;
  int noteOnIndex = 1;
  int chordDuration = 30;
  int noteOffIndex = noteOnIndex + chordDuration * 0.75;

  auto mixer{harness.createMixer(12)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  auto playChord = [&](int note1, int note2, int note3, bool sustain) {
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

  XCTAssertEqual(32, engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(0, engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0585853196681, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.139635398984, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0656754374504, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.0630209818482, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0279885157943, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.0638669133186, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.136517599225, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0657804235816, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.0629896596074, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0280037727207, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0638669133186, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.136517599225, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.0657804235816, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(0.0629896596074, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0280037727207, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.0638669133186, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.136517599225, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0657804235816, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0629896596074, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0280037727207, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0638669133186, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.136517599225, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.0657804235816, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(0.0629896596074, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.0280037727207, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[25], epsilon);

  // self.playAudio = YES;
  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testRolandPianoChordRenderCubic4thOrder {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::cubic4thOrder}};
  auto& engine{harness.engine()};
  harness.load(contexts.context2.path(), 0);

  int cycles = 5;
  int noteOnIndex = 1;
  int chordDuration = 30;
  int noteOffIndex = noteOnIndex + chordDuration * 0.75;

  auto mixer{harness.createMixer(12)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  auto playChord = [&](int note1, int note2, int note3, bool sustain) {
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

  XCTAssertEqual(32, engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(0, engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0584149733186, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.139659687877, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0654851198196, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.0635829642415, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0277795381844, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.0636894926429, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.136539652944, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0655902549624, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.0635517537594, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0277947913855, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0636894926429, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.136539652944, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.0655902549624, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(0.0635517537594, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0277947913855, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.0636894926429, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.136539652944, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0655902549624, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0635517537594, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0277947913855, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0636894926429, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.136539652944, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.0655902549624, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(0.0635517537594, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.0277947913855, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[25], epsilon);

  // self.playAudio = YES;
  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIProgramChange {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

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
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.renderUntil(mixer, harness.renders() * 0.5);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(1, engine.activeVoiceCount());

  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::programChange);
  midiEvent.data[1] = 23;
  midiEvent.length = 2;

  engine.doMIDIEvent(midiEvent);
  name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
  NSLog(@"name: |%@|", name);
  XCTAssertTrue([name isEqualToString:@"Bandoneon"]);
  XCTAssertEqual(0, engine.activeVoiceCount());

  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00312164006755, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.0106693943962, samples[1], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testYamahaPianoChordRender {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  int seconds = 3;
  int noteOnIndex = 1;
  int chordDuration = 30;
  int noteOffIndex = noteOnIndex + chordDuration * .75;

  auto mixer{harness.createMixer(seconds)};

  // Set NPRN state so that voices send 20% output to the chorus channel
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnMSB, 120);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Index::chorusEffectSend));
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 65);

  XCTAssertEqual(0, engine.activeVoiceCount());

  auto playChord = [&](int note1, int note2, int note3, bool sustain) {
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
  XCTAssertEqual(3, engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.duration()];
  [self playSamples: harness.chorusBuffer() count: harness.duration()];
}

// Render 1 second of audio at 48000.0 sample rate using all voices of an engine and interpolating using 4th-order cubic.
// Uses both effects buffers to account for mixing effort when they are active.
- (void)testEngineRenderPerformanceUsingCubic4thOrderInterpolation
{
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    auto harness{TestEngineHarness{48000.0, 96, SF2::Render::Voice::Sample::Interpolator::cubic4thOrder}};
    auto& engine{harness.engine()};
    harness.load(contexts.context0.path(), 0);
    std::vector<AUValue> samples;
    samples.reserve(8);

    int seconds = 1;
    auto mixer{harness.createMixer(seconds)};
    for (int voice = 0; voice < engine.voiceCount(); ++voice) harness.sendNoteOn(12 + voice);

    [self startMeasuring];

    harness.renderUntil(mixer, harness.renders() * 0.25);
    samples.push_back(harness.lastDrySample());
    harness.renderUntil(mixer, harness.renders() * 0.50);
    samples.push_back(harness.lastDrySample());
    harness.renderUntil(mixer, harness.renders() * 0.75);
    samples.push_back(harness.lastDrySample());
    harness.renderToEnd(mixer);
    samples.push_back(harness.lastDrySample());

    [self stopMeasuring];

    [self dumpSamples: samples];

    XCTAssertEqualWithAccuracy(-0.0181933436543, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00796244945377, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00321189756505, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.0141361160204, samples[3], epsilon);

    // [self playSamples: harness.dryBuffer() count: harness.duration()];
  }];
}

// Render 1 second of audio at 48000.0 sample rate using all voices of an engine and interpolating using linear
// algorithm. Uses both effects buffers to account for mixing effort when they are active.
- (void)testEngineRenderPerformanceUsingLinearInterpolation
{
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    auto harness{TestEngineHarness{48000.0, 96, SF2::Render::Voice::Sample::Interpolator::linear}};
    auto& engine{harness.engine()};
    harness.load(contexts.context0.path(), 0);
    std::vector<AUValue> samples;
    samples.reserve(8);

    int seconds = 1;
    auto mixer{harness.createMixer(seconds)};
    for (int voice = 0; voice < engine.voiceCount(); ++voice) harness.sendNoteOn(12 + voice);

    [self startMeasuring];

    harness.renderUntil(mixer, harness.renders() * 0.25);
    samples.push_back(harness.lastDrySample());
    harness.renderUntil(mixer, harness.renders() * 0.50);
    samples.push_back(harness.lastDrySample());
    harness.renderUntil(mixer, harness.renders() * 0.75);
    samples.push_back(harness.lastDrySample());
    harness.renderToEnd(mixer);
    samples.push_back(harness.lastDrySample());

    [self stopMeasuring];

    [self dumpSamples: samples];

    XCTAssertEqualWithAccuracy(-0.0182746388018, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00806812010705, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0031861460302, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.0140042249113, samples[3], epsilon);

    // [self playSamples: harness.dryBuffer() count: harness.duration()];
  }];
}

- (void)testEngineMIDINoteOnOffProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  // Note 1 on
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(1, engine.activeVoiceCount());

  // Note 2 on
  midiEvent.data[1] = 0x44;
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(2, engine.activeVoiceCount());

  // Render 20% of total
  int renderIndex = 0;
  harness.renderUntil(mixer, harness.renders() * 0.2);

  // Note 1 off
  midiEvent.data[0] = 0x80;
  midiEvent.data[1] = 0x40;
  midiEvent.length = 2;
  engine.doMIDIEvent(midiEvent);

  // Render another 20%
  harness.renderUntil(mixer, harness.renders() * 0.4);

  // Note 2 off
  midiEvent.data[1] = 0x44;
  engine.doMIDIEvent(midiEvent);

  // Render rest
  harness.renderToEnd(mixer);
  XCTAssertEqual(0, engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIPitchBendProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context2.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x64;
  midiEvent.length = 3;

  // Note 1 on
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(2, engine.activeVoiceCount());

  // Note 2 on
  midiEvent.data[1] = 0x44;
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(4, engine.activeVoiceCount());

  // Note 3 on
  midiEvent.data[1] = 0x47;
  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(6, engine.activeVoiceCount());

  // Render 20% of total
  int renderIndex = 0;
  harness.renderUntil(mixer, harness.renders() * 0.2);
  samples.push_back(harness.lastDrySample());

  // Pitch wheel all the way up
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::pitchBend);
  midiEvent.data[1] = 127;
  midiEvent.data[2] = 127;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.4);
  samples.push_back(harness.lastDrySample());

  // Pitch wheel all the way down
  midiEvent.data[1] = 0;
  midiEvent.data[2] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.6);
  samples.push_back(harness.lastDrySample());

  // Pitch wheel at center
  midiEvent.data[1] = 0;
  midiEvent.data[2] = 0x20;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.8);
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.118135415018, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.0529967471957, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0434629619122, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.024333762005, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.00972236786038, samples[4], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineExcludeClassNoteTermination
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context1.path(), 260);

  int seconds = 1.5;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  harness.sendNoteOn(46);
  harness.renderUntil(mixer, harness.renders() * 0.2);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendNoteOn(46);
  harness.renderUntil(mixer, harness.renders() * 0.4);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendNoteOn(46);
  harness.renderUntil(mixer, harness.renders() * 0.6);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendNoteOn(46);
  harness.renderUntil(mixer, harness.renders() * 0.8);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendNoteOn(46);
  harness.renderToEnd(mixer);
  XCTAssertEqual(1, engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIChannelPressure
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context1.path(), 14);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
  harness.sendNoteOn(67);
  harness.sendNoteOn(72);
  harness.renderUntil(mixer, harness.renders() * 0.2);
  samples.push_back(harness.lastDrySample());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::channelPressure);
  midiEvent.length = 2;

  midiEvent.data[1] = 127;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.6);
  samples.push_back(harness.lastDrySample());

  midiEvent.data[1] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0138967316598, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.00947172474116, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00546989124268, samples[2], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIKeyPressure // no effect as there is no modulator using it
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context1.path(), 14);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60, 127);
  harness.renderUntil(mixer, harness.renders() * 0.1);
  samples.push_back(harness.lastDrySample());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::keyPressure);
  midiEvent.data[1] = 60;
  midiEvent.length = 3;

  for (auto count = 1; count <= 4; ++count) {
    midiEvent.data[2] = 127;
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, harness.renders() * (0.1 + 0.2 * count));
    samples.push_back(harness.lastDrySample());

    midiEvent.data[2] = 32;
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, harness.renders() * (0.2 + 0.2 * count));
    samples.push_back(harness.lastDrySample());
  }

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.00668354937807, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0404301397502, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.0571423061192, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00673362473026, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0436884015799, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.023754844442, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.000322586420225, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0209613889456, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.0113112898543, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0113112898543, samples[9], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineSustainPedalProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context1.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(72, 127);
  harness.sendNoteOn(76, 127);
  harness.sendNoteOn(79, 127);
  harness.renderUntil(mixer, harness.renders() * 0.1);
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sustainPedalActive);

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = SF2::valueOf(MIDI::ControlChange::sustainSwitch);
  midiEvent.data[2] = 64;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertTrue(engine.channelState().pedalState().sustainPedalActive);

  harness.renderUntil(mixer, harness.renders() * 0.2);
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderUntil(mixer, harness.renders() * 0.4);
  XCTAssertTrue(engine.channelState().pedalState().sustainPedalActive);
  XCTAssertEqual(3, engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  midiEvent.data[2] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.5);
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sustainPedalActive);

  harness.sendNoteOn(72, 127);
  harness.sendNoteOn(76, 127);
  harness.sendNoteOn(79, 127);
  harness.renderUntil(mixer, harness.renders() * 0.7);
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderUntil(mixer, harness.renders() * 0.9);
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0495313704014, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0211332235485, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0019038640894, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00263028102927, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0211724154651, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.000255482824286, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(7.80675327405e-05, samples[6], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineSostenutoPedalProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context1.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(72, 127);
  harness.sendNoteOn(76, 127);
  harness.sendNoteOn(79, 127);
  harness.renderUntil(mixer, harness.renders() * 0.1);
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sostenutoPedalActive);

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = SF2::valueOf(MIDI::ControlChange::sostenutoSwitch);
  midiEvent.data[2] = 64;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertTrue(engine.channelState().pedalState().sostenutoPedalActive);

  harness.renderUntil(mixer, harness.renders() * 0.2);
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderUntil(mixer, harness.renders() * 0.5);
  XCTAssertTrue(engine.channelState().pedalState().sostenutoPedalActive);
  XCTAssertEqual(3, engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOn(74, 127);
  harness.sendNoteOn(78, 127);
  harness.sendNoteOn(81, 127);
  harness.renderUntil(mixer, harness.renders() * 0.7);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(6, engine.activeVoiceCount());

  harness.sendNoteOff(74);
  harness.sendNoteOff(88);
  harness.sendNoteOff(81);
  harness.renderUntil(mixer, harness.renders() * 0.9);
  XCTAssertEqual(6, engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(6, engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0495313704014, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0211332235485, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0149366548285, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.0159172601998, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.00340272067115, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.00402484135702, samples[5], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIControlChangeCC10ForPanning
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 18);

  int seconds = 4;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
  harness.sendNoteOn(64);
  harness.sendNoteOn(67);
  harness.renderUntil(mixer, harness.renders() * 0.2);
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = 10;
  midiEvent.length = 3;

  // Pan left
  auto steps = int(harness.renders() * 0.2);
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = 64 - (step / steps * 64);
    engine.doMIDIEvent(midiEvent);
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = 64 - (step / steps * 64);
    engine.doMIDIEvent(midiEvent);
    harness.renderOnce(mixer);
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = 64 + (step / steps * 63);
    engine.doMIDIEvent(midiEvent);
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = 64 + (step / steps * 63);
    engine.doMIDIEvent(midiEvent);
    harness.renderOnce(mixer);
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00463884416968, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.00463884416968, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.000323427491821, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.000315399491228, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.000132384127937, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.000125891529024, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.00489116832614, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.00454992894083, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.000839568732772, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.000761541479733, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.00401247292757, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.00354868778959, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.00236437702551, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.00203871633857, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.00601302320138, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.00518481060863, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.00125735113397, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00105691398494, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.00209156400524, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00171375484206, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00807644892484, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.00647045578808, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.00138890743256, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00108435284346, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.00160303444136, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.00121941731777, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.00266135856509, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.00197217869572, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.00231874198653, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.00171828526072, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.00342545518652, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.00247233454138, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.00430048536509, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.0030325348489, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.00153541564941, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.00105407857336, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.00484995450824, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0032406358514, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.000999168958515, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.000649611989502, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.00150331982877, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.000950726796873, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.00386417284608, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.00244377274066, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.000869361450896, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.000536509323865, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.00456920824945, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.00274111749604, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.00693331612274, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.00404176861048, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.000761519768275, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.000431198219303, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.000495558429975, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.000272435630905, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0023120183032, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.00123346596956, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.00199842266738, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.00106616225094, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.00514498632401, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.00267260614783, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.000393079273636, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.000197956222109, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00105498253834, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.00051477731904, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.000906208646484, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.000428169296356, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.00494545418769, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.00226107425988, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.00265549309552, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.00117897125892, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.00216935621575, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.000963138882071, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.00782275479287, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.00335606979206, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.00225426489487, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.000933747098316, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.00159314193297, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.000636566255707, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.00224273931235, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.000863602675963, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.000559184933081, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.000208292331081, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.000254325859714, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-9.47345542954e-05, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.00208889273927, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.000748343183659, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.00976543221623, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.00336060160771, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.0014785771491, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.00048813392641, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.00117124151438, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.000370415044017, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.000706437451299, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.000213689680095, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.00269276788458, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.000782321440056, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.000194456893951, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(5.64949004911e-05, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.00673857051879, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.00186623819172, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.00250842282549, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.000660880818032, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.00295163551345, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.00073811452603, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.000722523080185, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.000171063555172, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.00466441828758, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00105031649582, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.00164589821361, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.000348945788573, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.00522479927167, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.0011077063391, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(1.2832111679e-05, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(2.55246413872e-06, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.00972493272275, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.00180767732672, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.00251405267045, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.000434704183135, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.00318716932088, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.000515067134984, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.000756415945943, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.000112507288577, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.00148017588072, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.000201180024305, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.00011752860155, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-1.59740447998e-05, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0066968947649, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.000824648246635, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.000363105442375, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(4.00872086175e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(9.84219368547e-05, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(9.6156654763e-06, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.00634309789166, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.000549371819943, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.000576613703743, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(4.26474143751e-05, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(8.4170489572e-05, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(5.16283762408e-06, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.00844179932028, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.000517801439855, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.00320952758193, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.000156410591444, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.00659080408514, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.000238218315644, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.000770035898313, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-1.93571904674e-05, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.00152004370466, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-1.91024373635e-05, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.00130360154435, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.00521253235638, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.00381309306249, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.00381309306249, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.000672512280289, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.000689630280249, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.0020481699612, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.0021537989378, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.004153536167, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.00446504633874, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.00311541720293, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.00343462149613, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.0034488691017, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.00389960873872, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.00290588196367, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.00328565714881, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.00187054113485, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.00216933805496, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.000841193716042, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.00100072077475, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.000935700605623, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.00114198215306, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.0010425648652, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.00130133354105, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.00467048631981, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.00598225323483, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.00148889375851, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.00190706877038, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.00174367881846, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.00229222350754, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.00370319793001, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.00499728415161, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.00198810896836, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.00275455415249, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.000306838541292, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.000435132533312, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.00376139464788, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.00547900702804, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.00024944258621, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00036334869219, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.000919440703001, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.00137604027987, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.00233807228506, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.00359619176015, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.0015103390906, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.00238819723018, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0015404013684, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.00249607069418, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.00135981745552, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.00226669944823, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.00205962965265, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.00353312212974, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.000741779862437, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.00127246114425, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(5.71506097913e-06, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(1.00932084024e-05, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.00321692181751, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.00585155934095, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.00267160474323, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.00500767771155, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112783140503, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.00217116787098, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.00129855470732, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.002578524407, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.000178143149242, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.000353736802936, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.0019584253896, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.00401358865201, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.00200803414918, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.00424994854257, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.000881390413269, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.00192778976634, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.001701251138, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.00383186736144, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.0014559449628, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.00339370197617, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.00272418931127, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.00634988769889, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.000174786197022, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.000421971199103, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.00275337742642, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.00689090974629, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.000117601040984, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.000305404653773, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.00172279181425, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.00462503405288, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.000726698432118, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.00202847435139, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.000566473521758, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.00158122950234, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.000202455295948, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.000588306458667, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.00176682998426, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.00535179814324, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.00114973739255, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.0036354358308, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.00148053024895, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.00489448942244, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.00114825251512, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.00395231088623, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.000247432908509, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.000893425021786, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.000596914440393, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.0021553253755, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.000265140668489, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.00100636156276, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.00212830468081, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.00851084664464, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.00139595358633, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.00589610543102, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.000647424953058, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.00287519046105, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.000142865726957, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.000673864968121, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.000826447852887, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.00389816658571, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(-7.52286869101e-05, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(-0.000378199853003, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.000546239840332, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.0029386584647, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00109195581172, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.00631517870352, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112237234134, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.00694509595633, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.000587885268033, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.00395250599831, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.000606968300417, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.00408080639318, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(2.66738788923e-05, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.000196252367459, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(4.4024141971e-05, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.000357516342774, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.000220397021621, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.00199633138254, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.000674972543493, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.00690873386338, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(4.77963476442e-05, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.000551860779524, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.000179758237209, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.00207550544292, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.000125498336274, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.00169679848477, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.000461929797893, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.0075309141539, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.000132711778861, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.00272323051468, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.000187522164197, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.00518819037825, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(2.4569202651e-05, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.000977371702902, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(9.85923179542e-05, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.00784531421959, samples[301], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIReset {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  harness.sendNoteOn(60);
  harness.sendNoteOn(64);
  harness.sendNoteOn(67);
  XCTAssertEqual(3, engine.activeVoiceCount());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::reset);
  midiEvent.length = 1;
  engine.doMIDIEvent(midiEvent);

  XCTAssertEqual(0, engine.activeVoiceCount());
}

- (void)testEngineMIDILoad {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context2.path(), 0);

  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());

  const NSURL* url = contexts.context0.url();
  NSLog(@"URL: %@", url);
  const NSString* path = [url path];
  NSLog(@"path: %@", path);
  std::string tmp([path cStringUsingEncoding: NSUTF8StringEncoding],
                  [path lengthOfBytesUsingEncoding: NSUTF8StringEncoding]);
  auto payload = engine.createLoadFileUsePreset(tmp, 234);
  harness.sendRaw(payload);
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual(std::string("SFX"), engine.activePresetName());
}

- (void)testEngineOneVoicePerKey
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto address = Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled;
  harness.load(contexts.context0.path(), 0);

  int seconds = 1;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  harness.setParameter(Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled, 0.0);
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
  harness.renderUntil(mixer, harness.renders() * 0.25);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(1, engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.renderUntil(mixer, harness.renders() * 0.5);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(2, engine.activeVoiceCount());

  harness.sendAllOff();
  harness.setParameter(Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled, 1.0);
  XCTAssertTrue(engine.oneVoicePerKeyModeEnabled());

  harness.sendNoteOn(60);
  harness.renderUntil(mixer, harness.renders() * 0.75);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(1, engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(1, engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.00513585424051, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.0024097810965, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.00612613232806, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.000495888874866, samples[3], epsilon);

  XCTAssertNotEqualWithAccuracy(samples[1], samples[3], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineActiveVoiceCount
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto address = valueOf(Parameters::EngineParameterAddress::activeVoiceCount);
  AUParameter* param = [engine.parameterTree() parameterWithAddress:address];
  harness.load(contexts.context0.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.sendNoteOn(72);
  harness.renderUntil(mixer, harness.renders() * 0.1);
  XCTAssertEqual(2, engine.activeVoiceCount());
  XCTAssertEqual(2, param.value);

  harness.sendNoteOff(60);
  harness.renderUntil(mixer, harness.renders() * 0.5);
  XCTAssertEqual(1, engine.activeVoiceCount());
  XCTAssertEqual(1, param.value);

  harness.sendNoteOff(72);
  harness.renderToEnd(mixer);
  XCTAssertEqual(0, engine.activeVoiceCount());
  XCTAssertEqual(0, param.value);

  // Should be harmless
  param.value = 99;
  XCTAssertEqual(0, param.value);
}

- (void)testEngineParameterControlChangeForPanning
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto address = Index::pan;

  harness.load(contexts.context0.path(), 18);

  int seconds = 4;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
  harness.sendNoteOn(64);
  harness.sendNoteOn(67);
  harness.renderUntil(mixer, harness.renders() * 0.2);
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  // Pan left
  auto steps = int(harness.renders() * 0.2);
  for (auto step = 1_F; step <= steps; ++step) {
    harness.setParameter(Index::pan, step / steps * -500_F);
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    harness.setParameter(Index::pan, step / steps * -500_F);
    harness.renderOnce(mixer);
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    harness.setParameter(Index::pan, step / steps * 500_F);
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    harness.setParameter(Index::pan, step / steps * 500_F);
    harness.renderOnce(mixer);
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00463884416968, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.00463884416968, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.000322931911796, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.000315907062031, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.000131789478473, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.000126514001749, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.00486967293546, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.00457292748615, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.000834767357446, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.000766801647842, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.00397884938866, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.00358634628356, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.00234181783162, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.00206459010951, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.00601302320138, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.00518481060863, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.00125402456615, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00106085883453, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0020834649913, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00172359205317, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00804586801678, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.00650844257325, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.00138034834526, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00109522778075, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.00159147079103, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.00123447121587, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.00263951299712, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.00200132187456, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.00231603998691, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.00172192545142, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.00341767095961, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.00248308340088, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.00429093744606, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.00304603017867, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.00152876228094, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.00106370507274, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.00482435338199, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.00327862706035, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.000993002206087, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.000658999895677, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.0014912544284, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.000969542423263, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.00386032951064, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.00244983960874, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.000868517439812, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.000537874293514, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.00455624051392, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.00276261894032, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.00690778438002, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.00408525206149, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.000758109963499, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.000437165785115, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.000492533086799, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.000277867948171, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0022963359952, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.0012624214869, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.00199674535543, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.00106930010952, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.00513656483963, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.00268875644542, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.000392142101191, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.00019980633806, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00105172721669, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.000521395762917, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.000902132829651, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.00043669086881, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.00492029357702, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.00231531448662, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.00264236959629, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.00120809813961, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.00216784095392, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.000966545310803, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.00781217310578, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.00338062923402, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.00224983971566, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.000944359693676, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.00158809334971, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.000649059074931, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.00223450060003, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.000884701381437, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.000557197025046, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.000213553197682, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.000254325859714, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-9.47345542954e-05, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.00208771461621, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.00075162347639, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.00975482631475, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0033912640065, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.00147548108362, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.000497414439451, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.00116829620674, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.0003796024248, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.000704392092302, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.000220338130021, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.00268400320783, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.000811882084236, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.000194456893951, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(5.64949004911e-05, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.00673563033342, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.00187682069372, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.00250528077595, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.000672694179229, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.0029469395522, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.00075664545875, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.000721157295629, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.000176732894033, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.00465431204066, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00109423045069, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.00164196221158, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.000367022003047, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.00522479927167, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.0011077063391, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(1.28239626065e-05, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(2.5927729439e-06, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.00971630681306, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.00185348466039, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.00251127150841, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.000450491672382, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.00318302563392, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.000540082924999, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.000755321816541, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.000119631222333, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.00147787481546, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.000217442895519, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.000117503339425, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-1.61586503964e-05, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.00669427076355, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.000845683040097, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.000362912658602, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(4.17978444602e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(9.83430654742e-05, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(1.03883430711e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.00633858796209, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.000599172897637, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.000576186459512, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(4.80798771605e-05, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(8.4099243395e-05, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(6.22012885287e-06, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.0084409750998, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.000531061086804, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.00320902070962, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.000166492827702, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.00658917753026, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.000279624597169, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.000769898993894, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-2.41950547206e-05, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.00151984672993, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-3.1040119211e-05, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.00130352284759, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(-1.43335573739e-05, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.00521253235638, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.00377093628049, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.00385478883982, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.000667075335514, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.000694890972227, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.00203459663317, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.00216662557796, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.00412539951503, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.00449105584994, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.00310461153276, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.00344439200126, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.00344273960218, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.00390502135269, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.00286436476745, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.00332191330381, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.00185001303907, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.00218687090091, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.000833308207802, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.00100729661062, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.000928506720811, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.00114783889148, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.00103642081376, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.00130623194855, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.00465166987851, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.00599689688534, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.00146178517025, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.0019279262051, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.00171836954542, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.00231125764549, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.00365593563765, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.00503196381032, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.00196641357616, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.00277008349076, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.000304098590277, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.000437051989138, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.00373553391546, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.00549667142332, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.000243704591412, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.000367221946362, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.000902076775674, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.00138748530298, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.00229838932864, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.00362168205902, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.00148776406422, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.00240232539363, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.00152074988, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.00250809197314, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.00134554866236, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.00227519846521, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.00204295758158, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.0035427887924, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.000723717384972, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.00128282047808, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(5.58793544769e-06, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(1.01642217487e-05, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.00315238768235, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.00588657706976, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.00263219280168, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.00502850534394, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.00111074442975, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.0021799588576, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.00128232792486, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.00258663273416, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.000172564992681, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.00035649118945, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.00190149073023, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.00404087360948, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.00195447076112, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.00427484605461, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.000863182649482, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.0019360112492, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.0016650618054, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.00384773104452, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.00142924627289, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.00340503198095, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.00261406996287, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.00639600772411, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.000168136670254, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.000424664700404, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.00265568774194, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.00692914472893, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.000114235823276, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.000306679401547, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.00167183368467, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.00464369729161, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.000707548519131, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.00203523319215, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.000536569161341, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.00159162585624, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.000192260427866, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.000591716554482, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.00168254948221, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.00537889031693, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.0011039635865, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.00364959659055, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.00142662413418, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.00491047278047, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.00110472610686, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.00396469794214, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.000240408451646, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.000895341043361, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.000556183920708, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.00216619321145, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.000247713411227, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.00101079279557, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.00200777663849, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.00854008365422, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.00132175267208, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.00591318169609, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.000611244060565, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.00288309901953, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.000136508402647, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.000675181625411, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.000746679084841, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.00391422910616, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(-6.80868397467e-05, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(-0.000379550969228, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.00050001393538, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.00294687598944, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00100257107988, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.00632998440415, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.00102407950908, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.00696026813239, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.000544390524738, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.0039587309584, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.000517087173648, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.00409316644073, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(2.26610718528e-05, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.000196755980141, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(3.78404802177e-05, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.0003582239151, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.000189012818737, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.00199954700656, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.000577238446567, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.00691758515313, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(4.08578198403e-05, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.000552417943254, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.000130809901748, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.00207916437648, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(8.81564701558e-05, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.00169914751314, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.000319901737384, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.00753828324378, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-8.56402548379e-05, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.00272511690855, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.000106006482383, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.00519049586728, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(1.07499417936e-05, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.000977621413767, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.00784593448043, samples[301], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineChangePresetByIndex
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);
  XCTAssertEqual("Piano 1", engine.activePresetName());
  harness.sendRaw(engine.createUsePreset(1));
  XCTAssertEqual("Piano 2", engine.activePresetName());
  harness.sendRaw(engine.createUsePreset(128));
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("SynthBass101", engine.activePresetName());
  harness.sendRaw(engine.createUsePreset(engine.presetCount() - 1));
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("SFX", engine.activePresetName());
}

- (void)testEngineChangePresetByBankProgram
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);
  XCTAssertEqual("Piano 1", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgram(0, 1));
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 2", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgram(1, 38));
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("SynthBass101", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgram(128, 56));
  std::clog << engine.activePresetName() << '\n';
 }

- (void)testEngineAllSoundOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  int seconds = 1.0;
  auto mixer{harness.createMixer(seconds)};

  harness.sendNoteOn(60);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessage(MIDI::ControlChange::allSoundOff, 0));
  XCTAssertEqual(0, engine.activeVoiceCount());
}

- (void)testEngineAllNotesOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  int seconds = 1.0;
  auto mixer{harness.createMixer(seconds)};

  harness.sendNoteOn(60);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessage(MIDI::ControlChange::allNotesOff, 0));
  XCTAssertEqual(1, engine.activeVoiceCount());
}

- (void)testEngineResetAllControllers
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  int seconds = 1.0;
  auto mixer{harness.createMixer(seconds)};

  XCTAssertEqual(0, engine.channelState().continuousControllerValue(MIDI::ControlChange::bankSelectLSB));
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::bankSelectLSB, 123u);
  XCTAssertEqual(123u, engine.channelState().continuousControllerValue(MIDI::ControlChange::bankSelectLSB));

  harness.sendNoteOn(60);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessage(MIDI::ControlChange::resetAllControllers, 0));
  XCTAssertEqual(0, engine.channelState().continuousControllerValue(MIDI::ControlChange::bankSelectLSB));
  XCTAssertEqual(0, engine.activeVoiceCount());
}

- (void)testEngineMonoOn
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  XCTAssertFalse(engine.monophonicModeEnabled());

  harness.sendNoteOn(60);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessage(MIDI::ControlChange::monoOn, 0));
  XCTAssertTrue(engine.monophonicModeEnabled());
  XCTAssertEqual(0, engine.activeVoiceCount());
}

- (void)testEnginePolyOn
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  harness.sendRaw(engine.createChannelMessage(MIDI::ControlChange::monoOn, 0));
  XCTAssertTrue(engine.monophonicModeEnabled());

  harness.sendNoteOn(60);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessage(MIDI::ControlChange::polyOn, 0));
  XCTAssertFalse(engine.monophonicModeEnabled());
  XCTAssertEqual(0, engine.activeVoiceCount());
}

- (void)testEngineOmniOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessage(MIDI::ControlChange::omniOff, 0));
  XCTAssertEqual(0, engine.activeVoiceCount());
}

- (void)testEngineOmniOn
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(contexts.context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessage(MIDI::ControlChange::omniOn, 0));
  XCTAssertEqual(0, engine.activeVoiceCount());
}

@end
