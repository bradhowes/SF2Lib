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

- (void)testEngineMIDIControlChangeCC10ForPanning
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.file(), 1);

  int seconds = 4;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  std::vector<AUValue> samples;

  harness.sendNoteOn(60, 127);
  harness.sendNoteOn(64, 127);
  harness.sendNoteOn(67, 127);
  harness.renderUntil(mixer, harness.renders() * 0.2);
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = 10;
  midiEvent.length = 3;

  auto steps = 20_F;
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = 64 - (step / steps * 64);
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, harness.renders() * (0.2_F + step / steps * 0.2_F));
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = 64 - (step / steps * 64);
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, harness.renders() * (0.4_F + (steps - step) / steps * 0.2_F));
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = 64 + (step / steps * 63);
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, harness.renders() * (0.6_F + step / steps * 0.2_F));
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  for (int step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = 64 + (step / steps * 63);
    engine.doMIDIEvent(midiEvent);
    harness.renderUntil(mixer, harness.renders() * (0.8_F + (steps - step) / steps * 0.2_F));
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0194771923125, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0194771923125, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.00664452882484, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00602700468153, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0153075577691, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.012867346406, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.0147908180952, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0115475412458, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.0110485944897, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.00797436200082, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(-0.00528891058639, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(-0.00353393703699, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.000899174949154, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.000539424596354, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0105222575366, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.00578465964645, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(-0.00788849778473, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(-0.00397267751396, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0110416356474, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00504826381803, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00274691265076, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0011378088966, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.00431994628161, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00154761550948, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.00698794564232, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0.00220999703743, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(-0.00397346308455, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(-0.00110044539906, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(0.00984968338162, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(0.0023319972679, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127024538815, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.0025266748853, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(0.0242193713784, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(0.00360232498497, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(-0.00100246770307, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(-0.000110673427116, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.0145003469661, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.00107247254346, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.00455346796662, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.000164580778801, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(-0.0059318956919, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(-0.00383379450068, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(-0.000138568837428, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.00307142548263, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.000227168318816, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.00426005106419, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.000470314058475, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(0.000176784582436, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(2.62944959104e-05, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.0108516551554, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.00215852842666, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(0.00437349267304, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(0.00103546201717, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0148241203278, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.00410552043468, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(0.0257611665875, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(0.00814718753099, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(0.000597440637648, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(0.000214032363147, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.0106487357989, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.00441085128114, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(-0.00738325435668, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(-0.00337564223446, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(-0.00589906424284, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(-0.00297079165466, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(-0.00899006053805, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(-0.00494232773781, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.00289488118142, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.00173667096533, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(0.00775554962456, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(0.00518209300935, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.00295322202146, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.00213149841875, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(0.00771830976009, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(0.00602586660534, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.00171526148915, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.00144182797521, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.0101287979633, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.00918745435774, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.0150993019342, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.0150993019342, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.000315837562084, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.000339525286108, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.00825901515782, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.0095782969147, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(-0.0046588042751, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(-0.00581513857469, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(0.00358419190161, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(0.00483669154346, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.00800276175141, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.0116571616381, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.00145089242142, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.00229419814423, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(0.000440712086856, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(0.00077832210809, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(-0.000806064344943, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(-0.0015517398715, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(0.0040741590783, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(0.0086228447035, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.00222088233568, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.00517671462148, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(-0.0002234170679, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(-0.00058020465076, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.00333535252139, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.00969206169248, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.00144931476098, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00479129422456, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(-0.000133489767904, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(-0.000533810467459, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(-0.00113682902884, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(-0.00536216422915, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.00184642791282, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(0.0106785651296, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.00102681620046, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.00755477091298, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(0.00147810624912, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(0.0151292709634, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.00032239506254, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.00525605771691, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-3.45607404597e-05, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.00275011127815, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.000294391560601, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.00479951221496, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(0.0004610834294, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(0.00471945479512, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.000258360640146, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00190088106319, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.000930485199206, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(0.00538133550435, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(0.0026348780375, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(0.0124281197786, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(-0.00116417906247, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(-0.00465541891754, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(-0.0030729281716, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(-0.0101588023826, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.00492212222889, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(0.0143029903993, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.00228826608509, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00594252953306, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(0.00462947553024, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(0.0107909720391, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(-0.00335601437837, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(-0.00710291136056, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.00141513394192, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-0.00272424868308, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.0043699699454, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-0.0077176084742, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(0.000893869670108, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(0.00141341565177, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.0030219249893, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0.00440186401829, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.00167081388645, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.00225468119606, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.00591547042131, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.00738371349871, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.00416099838912, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.00482566934079, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(-0.0044827205129, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(-0.00481891958043, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(0.00647067371756, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(0.00647067371756, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(0.00647067371756, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(0.00647067371756, samples[163], epsilon);

  self.playAudio = YES;
  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIReset {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context0.file(), 0);

  harness.sendNoteOn(60);
  harness.sendNoteOn(64);
  harness.sendNoteOn(67);
  XCTAssertEqual(3, engine.activeVoiceCount());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = static_cast<uint8_t>(MIDI::CoreEvent::reset);
  midiEvent.length = 1;
  engine.doMIDIEvent(midiEvent);
  
  XCTAssertEqual(0, engine.activeVoiceCount());
}

- (void)testEngineMIDILoad {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context2.file(), 0);

  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());

  void* blob = malloc(sizeof(AUMIDIEvent) + 4096);
  AUMIDIEvent& midiEvent{*reinterpret_cast<AUMIDIEvent*>(blob)};

  uint8_t* pdata = midiEvent.data;
  pdata[0] = static_cast<uint8_t>(MIDI::CoreEvent::systemExclusive);
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
