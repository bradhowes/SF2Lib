// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <iostream>

#include <XCTest/XCTest.h>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.h"
#include "SF2Lib/Render/Engine/Engine.hpp"

using namespace SF2;
using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

@interface EngineTests : SamplePlayingTestCase
@end

@implementation EngineTests

- (void)setUp {
  [super setUp];
  self.playAudio = NO;
}

- (void)testInit {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertEqual(engine.voiceCount(), 32);
  XCTAssertEqual(engine.activeVoiceCount(), 0);
}

- (void)testLoad {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertFalse(engine.hasActivePreset());
  engine.load(contexts.context0.file(), 0);
  XCTAssertEqual(engine.presetCount(), 235);
  XCTAssertTrue(engine.hasActivePreset());
  engine.load(contexts.context1.file(), 10000);
  XCTAssertFalse(engine.hasActivePreset());
}

- (void)testUsePresetByIndex {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  engine.load(contexts.context0.file(), 0);
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
  engine.load(contexts.context0.file(), 0);
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
  engine.load(contexts.context2.file(), 0);

  int cycles = 5;
  int noteOnIndex = 1;
  int chordDuration = 30;
  int noteOffIndex = noteOnIndex + chordDuration * 0.75;

  auto mixer{harness.createMixer(12)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  auto playChord = [&](int note1, int note2, int note3, bool sustain) {
    harness.renderUntil(mixer, noteOnIndex);
    harness.sendNoteOn(note1, 64);
    harness.sendNoteOn(note2, 64);
    harness.sendNoteOn(note3, 64);
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

  XCTAssertEqual(14, engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(0, engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0658494010568, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.113060586154, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.0735827684402, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.0323020219803, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697059705853, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.0674980208278, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.113252699375, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0735213160515, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0323020219803, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697059705853, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(-0.0674980208278, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.113252699375, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.0735213160515, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0323020219803, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697059705853, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0674980208278, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.113252699375, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(-0.0735213160515, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(-0.0323020219803, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697059705853, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(-0.0674980208278, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.113252699375, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0735213160515, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0323020219803, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697059705853, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[25], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testRolandPianoChordRenderCubic4thOrder {
  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::cubic4thOrder}};
  auto& engine{harness.engine()};
  engine.load(contexts.context2.file(), 0);

  int cycles = 5;
  int noteOnIndex = 1;
  int chordDuration = 30;
  int noteOffIndex = noteOnIndex + chordDuration * 0.75;

  auto mixer{harness.createMixer(12)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  auto playChord = [&](int note1, int note2, int note3, bool sustain) {
    harness.renderUntil(mixer, noteOnIndex);
    harness.sendNoteOn(note1, 64);
    harness.sendNoteOn(note2, 64);
    harness.sendNoteOn(note3, 64);
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

  XCTAssertEqual(14, engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(0, engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0658824443817, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.113105282187, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.073615886271, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.0322798080742, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697460249066, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.0675312206149, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.113297276199, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.073554366827, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0322798080742, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697460249066, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(-0.0675312206149, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.113297276199, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.073554366827, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0322798080742, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697460249066, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0675312206149, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.113297276199, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(-0.073554366827, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(-0.0322798080742, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697460249066, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(-0.0675312206149, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.113297276199, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.073554366827, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0322798080742, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.0697460249066, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[25], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIProgramChange {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.file(), 0);

  NSString* name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
  NSLog(@"name: |%@|", name);
  XCTAssertTrue([name isEqualToString:@"Piano 1"]);

  int seconds = 1;
  auto mixer{harness.createMixer(seconds)};
  std::vector<AUValue> samples;

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(1, engine.activeVoiceCount());
  harness.renderUntil(mixer, harness.renders() * 0.5);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(1, engine.activeVoiceCount());

  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::programChange);
  midiEvent.data[1] = 23;
  midiEvent.length = 2;

  engine.doMIDIEvent(midiEvent);
  name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
  NSLog(@"name: |%@|", name);
  XCTAssertTrue([name isEqualToString:@"Bandoneon"]);
  XCTAssertEqual(0, engine.activeVoiceCount());

  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::noteOn);
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
  engine.load(contexts.context0.file(), 0);

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
    engine.load(contexts.context0.file(), 0);
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

    [self playSamples: harness.dryBuffer() count: harness.duration()];
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
    engine.load(contexts.context0.file(), 0);
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

    [self playSamples: harness.dryBuffer() count: harness.duration()];
  }];
}

- (void)testEngineMIDINoteOnOffProcessing
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.file(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::noteOn);
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
  engine.load(contexts.context2.file(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::noteOn);
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
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::pitchBend);
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

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineExcludeClassNoteTermination
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context1.file(), 260);

  int seconds = 1;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 46; // hi-hat
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  // Note 1 on repeatedly
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.1);
  XCTAssertEqual(1, engine.activeVoiceCount());
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.2);
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.3);
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.4);
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.5);
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.6);
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.7);
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.8);
  engine.doMIDIEvent(midiEvent);
  engine.doMIDIEvent(midiEvent);
  harness.renderUntil(mixer, harness.renders() * 0.9);
  harness.renderToEnd(mixer);
  XCTAssertEqual(1, engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIChannelPressure
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context1.file(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60, 32);
  harness.renderUntil(mixer, harness.renders() * 0.1);
  samples.push_back(harness.lastDrySample());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::channelPressure);
  midiEvent.length = 2;

  for (auto count = 1; count <= 4; ++count) {
    midiEvent.data[1] = 127;
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, harness.renders() * (0.1 + 0.2 * count));
    samples.push_back(harness.lastDrySample());

    midiEvent.data[1] = 32;
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, harness.renders() * (0.2 + 0.2 * count));
    samples.push_back(harness.lastDrySample());
  }

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.144146829844, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0552728325129, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.125654652715, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00773660978302, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0340545289218, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00285346154124, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.0432522296906, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0587924085557, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.00258183781989, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.00258183781989, samples[9], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIKeyPressure // no effect as there is no modulator using it
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context1.file(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60, 32);
  harness.renderUntil(mixer, harness.renders() * 0.1);
  samples.push_back(harness.lastDrySample());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::keyPressure);
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

  XCTAssertEqualWithAccuracy(-0.144146829844, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0382686220109, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.130335241556, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.0142596205696, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0892201662064, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.0443947091699, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.00772225763649, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.014249666594, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0327118746936, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.0327118746936, samples[9], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

@end
