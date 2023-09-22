// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <iostream>

#include <XCTest/XCTest.h>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.h"
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
  // self.playAudio = NO;
}

- (void)testInit {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertEqual(engine.voiceCount(), 32);
  XCTAssertEqual(engine.activeVoiceCount(), 0);
}

- (void)testDeprecatedLoad {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertFalse(engine.hasActivePreset());
  engine.load(contexts.context0.file(), 0);
  XCTAssertEqual(engine.presetCount(), 235);
  XCTAssertTrue(engine.hasActivePreset());
  engine.load(contexts.context1.file(), 10000);
  XCTAssertFalse(engine.hasActivePreset());
}

- (void)testLoad {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertFalse(engine.hasActivePreset());
  engine.load(contexts.context0.path(), 0);
  XCTAssertEqual(engine.presetCount(), 235);
  XCTAssertTrue(engine.hasActivePreset());
  engine.load(contexts.context1.path(), 10000);
  XCTAssertFalse(engine.hasActivePreset());
}

- (void)testUsePresetByIndex {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  engine.load(contexts.context0.path(), 0);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("Piano 1", engine.activePresetName());
  engine.usePreset(1);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 2", engine.activePresetName());
  engine.usePreset(2);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 3", engine.activePresetName());
  engine.usePreset(9999);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
}

- (void)testUsePresetByBankProgram {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  engine.load(contexts.context0.path(), 0);
  engine.usePreset(0, 0);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("Piano 1", engine.activePresetName());
  engine.usePreset(0, 1);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 2", engine.activePresetName());
  engine.usePreset(128, 56);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("SFX", engine.activePresetName());
  engine.usePreset(-1, -1);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  engine.usePreset(-1, 0);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  engine.usePreset(0, -1);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  engine.usePreset(129, 0);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  engine.usePreset(0, 128);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
}

- (void)testRolandPianoChordRenderLinear {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.path(), 0);

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

  XCTAssertEqual(9, engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(3, engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.006195360329, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.00193873886019, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00627591041848, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00230234791525, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.00636753998697, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.00606341706589, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.00193836505059, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0062759090215, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.00299934204668, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.00522136176005, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.00615657772869, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.00194043130614, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.00627591041848, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(0.00299935485236, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.00522136269137, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.00615657120943, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.00100242625922, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00580738997087, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.00492782704532, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00663954624906, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00825519766659, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.00103729229886, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.00723295565695, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(0.00455507496372, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.00671917386353, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(1.21050397865e-05, samples[25], epsilon);

  // self.playAudio = YES;
  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testRolandPianoChordRenderCubic4thOrder {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::cubic4thOrder}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.path(), 0);

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

  XCTAssertEqual(9, engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(3, engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00620820978656, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.00197225110605, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00628729024902, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00229898211546, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.00638039549813, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.00607410958037, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.0019718776457, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.00628729118034, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.00300289248116, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.00520273577422, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.00617005629465, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.00197396986187, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.00628729024902, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(0.00300290575251, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0052027371712, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.00617004279047, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.00106311473064, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00580877438188, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.00490780826658, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00661820638925, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00828596390784, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.00109814247116, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.00723214773461, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(0.00455955369398, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.00669949082658, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(1.34237343445e-05, samples[25], epsilon);

  // self.playAudio = YES;
  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIProgramChange {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.path(), 0);

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

  XCTAssertEqualWithAccuracy(0.00320581975393, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.00446751900017, samples[1], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testYamahaPianoChordRender {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.path(), 0);

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
    engine.noteOn(note1, 64);
    engine.noteOn(note2, 64);
    engine.noteOn(note3, 64);
    harness.renderUntil(mixer, noteOffIndex);
    if (!sustain) {
      engine.noteOff(note1);
      engine.noteOff(note2);
      engine.noteOff(note3);
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
    engine.load(contexts.context0.path(), 0);
    std::vector<AUValue> samples;
    samples.reserve(8);

    int seconds = 1;
    auto mixer{harness.createMixer(seconds)};
    for (int voice = 0; voice < engine.voiceCount(); ++voice) engine.noteOn(12 + voice * 1, 64);

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

    XCTAssertEqualWithAccuracy(-0.0175423678011, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.000576077960432, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00417161174119, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-0.00838535279036, samples[3], epsilon);

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
    engine.load(contexts.context0.path(), 0);
    std::vector<AUValue> samples;
    samples.reserve(8);

    int seconds = 1;
    auto mixer{harness.createMixer(seconds)};
    for (int voice = 0; voice < engine.voiceCount(); ++voice) engine.noteOn(12 + voice * 1, 64);

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

    XCTAssertEqualWithAccuracy(-0.0175696294755, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.000573705183342, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00413661915809, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-0.00841129478067, samples[3], epsilon);

    // [self playSamples: harness.dryBuffer() count: harness.duration()];
  }];
}

- (void)testEngineMIDINoteOnOffProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.path(), 0);

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
  engine.load(contexts.context2.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = SF2::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
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

  XCTAssertEqualWithAccuracy(-0.189819633961, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.064623221755, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00838514696807, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.0279013551772, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126082124189, samples[4], epsilon);

  // self.playAudio = true;
  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineExcludeClassNoteTermination
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context1.path(), 260);

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
  engine.load(contexts.context1.path(), 14);

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

  XCTAssertEqualWithAccuracy(-0.0145196141675, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.0170472636819, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00227707717568, samples[2], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIKeyPressure // no effect as there is no modulator using it
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context1.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60);
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

  XCTAssertEqualWithAccuracy(-0.0635724663734, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0311195515096, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.0582012012601, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00877243559808, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0498164817691, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.0462966524065, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.00346615817398, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0375473424792, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0343575663865, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.0343575663865, samples[9], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineSustainPedalProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context1.path(), 0);

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

  XCTAssertEqualWithAccuracy(-0.0529702976346, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.0153270084411, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00318588037044, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00134005001746, samples[3], epsilon);

  XCTAssertEqualWithAccuracy(-0.0153976893052, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(8.56176557136e-05, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-5.57662788196e-05, samples[6], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineSostenutoPedalProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context1.path(), 0);

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

  XCTAssertEqualWithAccuracy(-0.0529702976346, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.0153270084411, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.000906414352357, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.0282810628414, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.00963072106242, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00154553796165, samples[5], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIControlChangeCC10ForPanning
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.path(), 18);

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

  XCTAssertEqualWithAccuracy(0.0438985228539, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0438985228539, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00476486794651, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00464659370482, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.00119299255311, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00113448407501, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.0437168031931, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0406668372452, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.006344712805, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.00575505243614, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0362575277686, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0320666693151, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.0217071641237, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0187172964215, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0579856261611, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0499988868833, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0127565516159, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.010723002255, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0177922174335, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0145783238113, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0747983977199, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0599248111248, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0124354250729, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00970863178372, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.0136276688427, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.0103664742783, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.0273174755275, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.0202433951199, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.0213691294193, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.0158354230225, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.0340691953897, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.0245895590633, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.0383851677179, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.0270677246153, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.0144526716322, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.0099219083786, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.0444997027516, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0297337528318, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.00898135919124, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.00583925144747, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.0144744003192, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.00915387179703, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.0369104854763, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.023342859, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.00723454356194, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.0044646570459, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.0439191460609, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.0263475719839, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.0638060122728, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.0371956452727, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.00805523619056, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.00456114625558, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.0036239377223, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.00199227570556, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0221899226308, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.0118383634835, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.0166361182928, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.00887539610267, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.0451910048723, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.0234748497605, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.00316394446418, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.0015933746472, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.0101071391255, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.00493176467717, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.00746635254472, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.00352773349732, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.0478275381029, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.0218668729067, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.0255180187523, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.0113293481991, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.0193810015917, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.00860466994345, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.0720521137118, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.0309113524854, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.0225616246462, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00934533029795, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.0135467555374, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.00541283097118, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.0207537710667, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.00799157097936, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.00505181308836, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.00188176287338, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.00304975872859, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.00113601307385, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.0186825729907, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.00669300882146, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.0918177515268, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0315974652767, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.0153613127768, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.0050713471137, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.00842144526541, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.00266335369088, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.0101417358965, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.00306776631624, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254373028874, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.00739022018388, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.00243199244142, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(0.000706559978426, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.0628359094262, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.0174023211002, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.0230594649911, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.00607535429299, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.0259799975902, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.00649680942297, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.00720898341388, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.00170678878203, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.0419155471027, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00943838991225, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.0182448849082, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.00386808719486, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.0485418625176, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.010291329585, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.00362548604608, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(0.000721154036, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.0896196588874, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.0166585631669, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.024065265432, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.0041611189954, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.0309803709388, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.005006628111, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.00879063457251, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.00130749540403, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.014509383589, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.00197206158191, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.00149372406304, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-0.000203021336347, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0605151802301, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00745177362114, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.000852644443512, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(9.41327307373e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(-0.000971630215645, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(-9.49268578552e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.0627212673426, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.00543225090951, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.00378286838531, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(0.000279787927866, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.00117589347064, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(7.21266260371e-05, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.0771482363343, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00473210355267, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.0316984653473, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.00154476799071, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.0601314678788, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.0021733941976, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.00834066979587, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-0.000209668040043, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.0150389904156, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-0.000188995458302, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.00905133038759, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.0481735356152, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.0360851921141, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.0360851921141, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.00649905949831, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.00666448567063, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.0170454755425, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.0179245527834, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.0393110886216, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.0422593727708, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.028542753309, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.0314672328532, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.0335884392262, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.0379781797528, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.0257009062916, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.0290598068386, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.0181412827224, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.0210391376168, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.0077265324071, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.0091918213293, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.00916906446218, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.0111904479563, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.00894224643707, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.0111617483199, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.0428757183254, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.0549179166555, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.0138203334063, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.0177019536495, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.0159455295652, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.020961843431, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.0334564708173, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.0451478734612, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.0184770207852, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.0256001818925, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.00418476667255, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.00593448616564, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.0350299403071, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.0510260984302, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.00301900086924, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00439760368317, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.00884738378227, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.0132410442457, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.0217525046319, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.0334575548768, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.0132342036813, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0209263525903, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0144225712866, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.0233703739941, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.0130677279085, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.0217827819288, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.0204356778413, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.035055693239, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.00641494756564, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.0110043054447, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(0.000472107902169, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(0.00083376839757, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.0293808858842, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.0534436292946, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.0244559217244, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.0458403751254, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.00955147668719, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.0183873735368, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.0129307806492, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.0256764963269, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.00206526461989, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.00410096906126, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.0179459676147, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.0367783904076, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.0194615405053, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.0411898158491, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.00857103057206, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.0187466815114, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.0156598165631, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.0352718830109, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.0146330818534, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.034108646214, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254342406988, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.0592853650451, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.00100912386551, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.00243623927236, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.0250865872949, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.0627844929695, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.000873034354299, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.00226723216474, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.016534788534, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.0443895533681, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.00681802816689, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.0190315470099, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.0055492091924, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.0154898203909, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.00201171915978, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.00584577210248, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.0172242671251, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.0521729961038, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.01049778983, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.0331937000155, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.0137878051028, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.0455811470747, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.0104975774884, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.0361328981817, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.00229374784976, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.00828221440315, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.00577918579802, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.0208673551679, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.00285406131297, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.0108328051865, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.0195547007024, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.078197017312, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.0129959415644, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.0548911094666, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.00608550710604, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.0270255152136, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.0011160527356, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.00526416860521, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.00815225578845, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.0384523384273, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(6.98491930962e-07, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(3.51294875145e-06, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.0048768715933, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.0262365713716, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00994438305497, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.057511985302, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.0104537997395, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.0646867677569, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.00512197380885, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.0344363674521, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.00574507098645, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.0386256091297, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(0.000291847623885, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.00214726105332, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(0.000385252060369, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.00312859937549, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.00199435232207, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.0180646181107, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.00626913178712, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.0641681849957, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(0.000652935123071, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.00753885135055, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.00157851004042, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.0182256232947, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.00130341644399, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.017622821033, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.00448112003505, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.0730564072728, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.00133059290238, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.0273036137223, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.00174834521022, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.0483715981245, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(0.000210535014048, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.00837515760213, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0.000915802142117, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.0728733837605, samples[301], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIReset {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.path(), 0);

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
  engine.load(contexts.context2.path(), 0);

  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());

  void* blob = malloc(sizeof(AUMIDIEvent) + 4096);
  AUMIDIEvent& midiEvent{*reinterpret_cast<AUMIDIEvent*>(blob)};

  uint8_t* pdata = midiEvent.data;
  pdata[0] = SF2::valueOf(MIDI::CoreEvent::systemExclusive);
  pdata[1] = 0x7E; // Custom command for SF2Lib
  pdata[2] = 0x00;
  pdata[3] = 1;
  pdata[4] = 106; // preset 234 (last one of the FreeFont)

  const NSURL* url = contexts.context0.url();
  NSLog(@"URL: %@", url);
  const NSString* path = [url path];
  NSLog(@"path: %@", path);
  std::string tmp([path cStringUsingEncoding: NSUTF8StringEncoding],
                  [path lengthOfBytesUsingEncoding: NSUTF8StringEncoding]);
  auto encoded = SF2::Utils::Base64::encode(tmp);
  memcpy(pdata + 5, encoded.data(), encoded.size());
  midiEvent.length = encoded.size() + 5;

  engine.doMIDIEvent(midiEvent);

  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual(std::string("SFX"), engine.activePresetName());

  free(blob);
}

@end
