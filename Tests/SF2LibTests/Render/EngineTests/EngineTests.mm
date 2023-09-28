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
  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
  XCTAssertFalse(engine.portamentoModeEnabled());
  XCTAssertEqual(100, engine.portamentoRate());
  XCTAssertTrue(engine.retriggerModeEnabled());
}

- (void)testPortamento {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  auto pt = engine.parameterTree();
  auto pr = [pt parameterWithAddress:SF2::valueOf(Parameters::EngineParameterAddress::portamentoRate)];
  auto pe = [pt parameterWithAddress:SF2::valueOf(Parameters::EngineParameterAddress::portamentoModeEnabled)];

  XCTAssertFalse(engine.portamentoModeEnabled());
  pe.value = 1.0;
  XCTAssertTrue(engine.portamentoModeEnabled());
  pr.value = 12345;
  XCTAssertEqual(12345, engine.portamentoRate());

  [pr setValue:987];
  XCTAssertEqual(987, engine.portamentoRate());
  XCTAssertEqual(987, pr.value);

  [pe setValue:0.0];
  XCTAssertFalse(engine.portamentoModeEnabled());
  XCTAssertEqual(0.0, pe.value);
}

- (void)testPhonicMode {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  auto pt = engine.parameterTree();
  auto pe = [pt parameterWithAddress:SF2::valueOf(Parameters::EngineParameterAddress::polyphonicModeEnabled)];

  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.monophonicModeEnabled());
  XCTAssertEqual(1.0, pe.value);

  pe.value = 0.0;
  XCTAssertFalse(engine.polyphonicModeEnabled());
  XCTAssertTrue(engine.monophonicModeEnabled());
  XCTAssertEqual(0.0, pe.value);

  pe.value = 1.0;
  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.monophonicModeEnabled());
  XCTAssertEqual(1.0, pe.value);
}

- (void)testOneVoicePerKey {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  auto pt = engine.parameterTree();
  auto ov = [pt parameterWithAddress:SF2::valueOf(Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled)];

  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
  ov.value = 1.0;
  XCTAssertTrue(engine.oneVoicePerKeyModeEnabled());
  ov.value = 0.0;
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
}

- (void)testRetriggering {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  auto pt = engine.parameterTree();
  auto rt = [pt parameterWithAddress:SF2::valueOf(Parameters::EngineParameterAddress::retriggerModeEnabled)];
  XCTAssertEqual(1.0, rt.value);
  XCTAssertTrue(engine.retriggerModeEnabled());
  rt.value = 0.0;
  XCTAssertFalse(engine.retriggerModeEnabled());
  rt.value = 1.0;
  XCTAssertTrue(engine.retriggerModeEnabled());
}

- (void)testLoad {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual(engine.load(contexts.context0.path(), 0), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqual(engine.presetCount(), 235);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual(engine.load(contexts.context1.path(), 10000), SF2::IO::File::LoadResponse::ok);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual(engine.load(contexts.context2.path(), 0), SF2::IO::File::LoadResponse::ok);
}

- (void)testUsePresetByIndex {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear);
  XCTAssertEqual(engine.load(contexts.context0.path(), 0), SF2::IO::File::LoadResponse::ok);
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
  XCTAssertEqual(engine.load(contexts.context0.path(), 0), SF2::IO::File::LoadResponse::ok);
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

  XCTAssertEqualWithAccuracy(0.00277469842695, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.00135909882374, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00272743590176, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00214356603101, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.00282307644375, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.00272667175159, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.00136159115937, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.00272492575459, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0021473239176, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.00172226526774, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.00260080210865, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(-2.63341371465e-05, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.00166539021302, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.00227133068256, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.00172323174775, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.00259839417413, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(-2.98699360428e-05, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00166425155476, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(-0.00227381335571, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00172281870618, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00149428995792, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.00113378698006, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.00293206004426, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00203693681397, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.00296338787302, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0.00120984541718, samples[25], epsilon);

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

  XCTAssertEqualWithAccuracy(0.00278814975172, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.00139056809712, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00274081784301, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00209575844929, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.00283911381848, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.00274088559672, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.00139301270247, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.00273824925534, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.00209966022521, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.00169634819031, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.00261308439076, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(-3.37290657626e-06, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.00163713062648, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.00222559995018, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.00169715855736, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.00261049950495, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(-7.16821341484e-06, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00163603131659, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(-0.00222817435861, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00169661210384, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00146438076627, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.00118012970779, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.00292897666804, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00201967521571, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.00296060508117, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0.00121395813767, samples[25], epsilon);

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
  XCTAssertEqualWithAccuracy(-0.00987235922366, samples[1], epsilon);

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
    engine.load(contexts.context0.path(), 0);
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

    XCTAssertEqualWithAccuracy(-0.0175423678011, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00750154070556, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00115390331484, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.0123179899529, samples[3], epsilon);

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

    XCTAssertEqualWithAccuracy(-0.0175696294755, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00756920967251, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00128235761076, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.0122199002653, samples[3], epsilon);

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

  XCTAssertEqualWithAccuracy(-0.118742279708, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.055044580251, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.043859295547, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.0239746123552, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0102841500193, samples[4], epsilon);

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
  XCTAssertEqualWithAccuracy(0.0093383230269, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00529375206679, samples[2], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineMIDIKeyPressure // no effect as there is no modulator using it
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  engine.load(contexts.context1.path(), 14);

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

  XCTAssertEqualWithAccuracy(-0.00456297583878, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.041143476963, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.0563844367862, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00480544846505, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0430959314108, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.0230379682034, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-9.20867194054e-07, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0213786754757, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.0114540858194, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0114540858194, samples[9], epsilon);

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
  XCTAssertEqualWithAccuracy(0.0238729957491, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00398920662701, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.000233859056607, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0239711012691, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-4.49934086646e-05, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(8.02297581686e-05, samples[6], epsilon);

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
  XCTAssertEqualWithAccuracy(0.0238729957491, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00382569339126, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00445476220921, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.000225194264203, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00452476646751, samples[5], epsilon);

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

  XCTAssertEqualWithAccuracy(0.0047038118355, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0047038118355, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.000510564655997, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.000497891334817, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.000127831473947, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00012156215962, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.00468433974311, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.00435752980411, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.000679848250002, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.000616664940026, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.00388506404124, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0034360056743, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.00232596462592, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.00200559431687, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.00621327152476, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0053574773483, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.00136688922066, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00114899035543, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.00190647051204, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00156209548004, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00801479257643, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.00642105937004, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.00133247987833, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00104029860813, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.00146023090929, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.00111078761984, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.00292712007649, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.00216911896132, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.00228974362835, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.00169679615647, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.00365057960153, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.00263481866568, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.00411304505542, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.00290035898797, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.00154863181524, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.00106315151788, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.00476822955534, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.00318602891639, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.000962370075285, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.00062568706926, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.00155095977243, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.000980854965746, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.00395502988249, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.00250123231672, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.000775195308961, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.000478396716062, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.00470602139831, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.0028231930919, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.00683693774045, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.00398558517918, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.000863134046085, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.000488735560793, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.000388311804272, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.00021347621805, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.00237769307569, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.00126850348897, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.00178259192035, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.000951015856117, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.00484230369329, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.00251537538134, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.000339022779372, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.000170733110281, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00108299928252, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.000528448086698, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.000800034147687, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.000378003547667, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.00512481294572, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.00234307767823, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.00273430487141, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.00121396163013, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.00207671150565, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.000922006904148, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.00772052304819, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.00331221055239, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.00241752155125, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00100137013942, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.00145156099461, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.000579995336011, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.00222380668856, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.000856312341057, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.000541311572306, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.000201634538826, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.000326787529048, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.000121726014186, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.00200187391602, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.000717168848496, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.00983844976872, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.00338572938927, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.00164599437267, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.000543404661585, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.000902374275029, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.000285383488517, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.00108670676127, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.000328716996592, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.00272565637715, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.00079187634401, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.000260592903942, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(7.5709191151e-05, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.0067329891026, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.00186469242908, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.00247086631134, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.000650985981338, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.00278380699456, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.000696145696566, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.000772456405684, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.000182885676622, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.00449133198708, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00101134169381, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.00195497460663, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.000414472946431, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.00520135462284, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.00110273587052, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.000388477812521, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(7.72730563767e-05, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.00960291922092, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.00178499717731, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.00257863965817, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.000445871904958, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.00331960665062, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.000536469859071, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.000941933365539, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.000140100659337, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.00155470846221, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.000211310165469, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.000160055467859, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-2.175415284e-05, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0064843185246, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.000798471854068, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(9.13625117391e-05, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(1.00865145214e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(-0.000104112259578, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(-1.01716141216e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.00672070495784, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.000582076143473, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.000405341619626, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(2.99798266497e-05, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.000125999096781, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(7.72852945374e-06, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.00826658308506, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00050705409376, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.00339655205607, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.000165524877957, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.00644320296124, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.000232883379795, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.000893718679436, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-2.24663381232e-05, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.00161145685706, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-2.02512292162e-05, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.000969867454842, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.00516188750044, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.00386659801006, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.00386659801006, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.000696386618074, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.000714112480637, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.0018264555838, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.00192065059673, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.00421225884929, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.00452817324549, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.00305841118097, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.00337177468464, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.00359906605445, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.00406943494454, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.00275390176103, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.00311381439678, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.00194387347437, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.00225438433699, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.000827912939712, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.000984921352938, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.000982483150437, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.00119907816406, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.000958179007284, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.00119600293692, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.00459421612322, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.00588456122205, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.00148087530397, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.00189679849427, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.00170859438367, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.00224610185251, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.00358492555097, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.00483768153936, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.00197984836996, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.00274310866371, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.000448405742645, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.000635891687125, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.00375352567062, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.00546754524112, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.000323491694871, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.000471211737022, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.000948014203459, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.00141880346928, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.0023308226373, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.00358504150063, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.001418070402, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0022422990296, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0015454061795, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.00250418088399, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.00140023231506, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.00233406736515, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.00218972214498, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.00375628541224, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.000687374034896, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.00117913261056, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(5.05873467773e-05, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(8.93399119377e-05, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.00314821861684, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.00572658795863, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.00262049934827, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.00491188466549, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.00102345913183, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.00197024270892, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.00138555816375, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.00275128614157, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.000221297028475, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.000439426861703, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.00192294502631, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.003940875642, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.00208534160629, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.00441356794909, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.000918402511161, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.00200874311849, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.00167797959875, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.0037794506643, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.00156796292868, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.00365480780602, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.00272532785311, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.00635254150257, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.000108129577711, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.00026104785502, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.00268807634711, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.00672747986391, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-9.35472780839e-05, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.000242938287556, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.00177173444536, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.00475642597303, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.000730564934202, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.00203926721588, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.000594608427491, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.00165976420976, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.000215559615754, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.000626385619398, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.00184561358765, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.00559043744579, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.00112485839054, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.00355676934123, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.00147739006206, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.0048841079697, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112483568955, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.00387170980684, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.000245779549005, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.000887455244083, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.000619250931777, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.0022359774448, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.000305818160996, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.00116075575352, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.00209532375447, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.0083789601922, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.00139254017267, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.0058816880919, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.000652073824313, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.00289583625272, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.000119587260997, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.000564065994695, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.000873529934324, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.00412024231628, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(7.48550519347e-08, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(3.76254320145e-07, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.000522566202562, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.0028112991713, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00106555980165, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.0061625209637, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112014473416, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.00693131238222, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.000548829440959, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.00368992332369, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.000615595490672, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.00413880869746, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(3.12720367219e-05, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.000230083183851, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(4.12805238739e-05, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.000335235381499, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.00021369868773, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.00193565874361, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.000671749585308, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.00687574455515, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(6.99632801116e-05, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.000807802425697, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.000169140417711, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.00195291126147, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.000139663607115, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.00188831961714, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.000480160641018, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.00782813504338, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.000142575590871, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.00292563508265, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.000187338562682, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.0051831100136, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(2.2559232093e-05, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.000897414342035, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(9.81299672276e-05, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.00780852418393, samples[301], epsilon);

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

  auto blob = std::array<char, sizeof(AUMIDIEvent) + 4096>();
  AUMIDIEvent& midiEvent{*reinterpret_cast<AUMIDIEvent*>(blob.data())};

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
}

- (void)testEngineOneVoicePerKey
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto address = valueOf(Parameters::EngineParameterAddress::oneVoicePerKeyModeEnabled);
  AUParameter* param = [engine.parameterTree() parameterWithAddress:address];

  engine.load(contexts.context0.path(), 0);

  int seconds = 1;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(0, engine.activeVoiceCount());

  param.value = false;
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
  param.value = true;
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

  XCTAssertEqualWithAccuracy(-0.00523802358657, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.00267931469716, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(-0.00523802358657, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.00197477918118, samples[3], epsilon);

  XCTAssertNotEqualWithAccuracy(samples[1], samples[3], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testEngineActiveVoiceCount
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto address = valueOf(Parameters::EngineParameterAddress::activeVoiceCount);
  AUParameter* param = [engine.parameterTree() parameterWithAddress:address];
  engine.load(contexts.context0.path(), 0);

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
  auto address = valueOf(Index::pan);
  AUParameter* param = [engine.parameterTree() parameterWithAddress:address];

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

  // Pan left
  auto steps = int(harness.renders() * 0.2);
  for (auto step = 1_F; step <= steps; ++step) {
    param.value = step / steps * -500_F;
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    param.value = step / steps * -500_F;
    harness.renderOnce(mixer);
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    param.value = step / steps * 500_F;
    harness.renderOnce(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    param.value = step / steps * 500_F;
    harness.renderOnce(mixer);
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0047038118355, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0047038118355, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.000509781995788, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.000498692737892, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.000127257080749, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.000122163211927, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.00466375332326, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.004379555583, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.000675960269291, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.000620924402028, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.00385250849649, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.00347246835008, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.00230377167463, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0020310478285, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.00621327152476, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0053574773483, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.00136327277869, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00115327886306, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.00189908803441, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.00157106225379, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.00798444449902, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.00645875651389, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0013242685236, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00105073163286, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.00144969730172, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112450041343, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.00290309288539, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.0022011725232, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.00228707538918, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.00170039082877, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.00364228384569, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.00264627416618, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.00410391297191, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.00291326618753, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.00154192105401, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.00107286090497, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.00474305963144, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0032233800739, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.000956430449151, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.000634729280137, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.00153851194773, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.00100026698783, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.00395109597594, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.00250744167715, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.000774442916736, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.000479613780044, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.0046926648356, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.00284533831291, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.00681176036596, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.00402846420184, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.00085926882457, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.000495499349199, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.000385941239074, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.000217733002501, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.00236156536266, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.00129828148056, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.00178109528497, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.000953814946115, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.00483437767252, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.00253057549708, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.000338214362273, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.000172328902408, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00107965769712, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.00053524231771, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.000796436448582, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.000385526800528, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.00509874057025, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.00239928509109, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.00272079184651, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.00124395289458, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.00207526073791, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.000925267930143, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.00771007919684, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.00333644915372, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.00241277576424, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00101275136694, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.001446961076, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.000591377844103, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.00221563735977, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.000877232872881, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.000539387110621, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.000206727301702, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.000326787529048, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.000121726014186, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.00200074492022, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.000720312469639, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.00982776470482, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0034166208934, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.00164254778065, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.00055373593932, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.000900105049368, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.000292461860226, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.00108356052078, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.000338944315445, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.00271678459831, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.000821797992103, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.000260592903942, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(7.5709191151e-05, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.0067300517112, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.00187526619993, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.0024677712936, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.000662622391246, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.00277937785722, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.000713622954208, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.000770996441133, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.000188946869457, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.0044816005975, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00105362595059, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.00195029960014, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.000435943540651, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.00520135462284, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.00110273587052, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.00038823322393, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(7.84931180533e-05, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.00959440134466, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.00183023000136, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.00257578724995, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.000462065130705, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.00331529090181, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.000562525179703, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.000940571189858, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.000148971827002, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.00155229121447, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.000228392018471, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.000160021008924, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-2.20055226237e-05, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.00648177787662, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00081883900566, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(9.13140829653e-05, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(1.051693107e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(-0.000104029197246, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(-1.09889733722e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.00671592634171, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.00063484191196, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.000405041035265, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(3.37987148669e-05, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.000125892227516, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(9.31123213377e-06, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.00826577562839, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.000520038534887, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.00339601538144, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.000176194633241, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.00644161226228, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.000273362355074, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.000893560005352, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-2.80812564597e-05, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.00161124800798, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-3.29068279825e-05, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.000969808897935, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(-1.06640363811e-05, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.00516188750044, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.00382384983823, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.00390887865797, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.000690756714903, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.000719559844583, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.00181435188279, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.00193208851852, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.00418372452259, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.00455455016345, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.00304780341685, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.00338136637583, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.00359266949818, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.00407508388162, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.00271455594338, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.00314817437902, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.00192254013382, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.00227260426618, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.000820151879452, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.000991393346339, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.000974929658696, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.00120522757061, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.000952532282099, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.00120050483383, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.00457570608705, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.00589896505699, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.00145391304977, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.00191754358821, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.00168379431125, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.00226475298405, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.00353917293251, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.00487125338987, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.00195824331604, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.00275857374072, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.000444401754066, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.000638696365058, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.00372771918774, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.00548517238349, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.000316050252877, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00047623476712, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.0009301105747, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.00143060425762, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.00229126308113, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.00361045310274, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.00139687454794, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0022555643227, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.00152569101192, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.00251624081284, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.00138553930447, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.00234281923622, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.00217199698091, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.00376656185836, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.000670636305586, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.00118873198517, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(4.94606792927e-05, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(8.99687875062e-05, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.00308506237343, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.00576085783541, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.00258184107952, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.00493231415749, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.00100795342587, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.00197821995243, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.00136824406218, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.0027599374298, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.000214367522858, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.000442848540843, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.00186704192311, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.00396766606718, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.00202971603721, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.00443942379206, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.000899429956917, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.00201730965637, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.00164228514768, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.00379509711638, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.001539209974, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.00366700952873, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.00261516263708, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.00639868108556, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.000104015809484, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.000262714107521, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.00259270332754, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.00676480773836, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-9.08704241738e-05, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.000243952265009, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.00171932880767, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.00477561959997, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.0007113130996, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.00204606167972, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.000563218898606, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.0016706767492, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.000204704789212, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.000630016671494, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.00175757519901, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.0056187370792, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.00108007516246, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.00357062346302, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.00142359826714, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.00490005686879, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.0010821968317, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.00388384354301, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.00023880196386, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.000889358110726, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.00057699624449, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.00224725203589, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.000285717076622, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.00116586685181, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.00197666371241, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.00840774364769, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.0013185206335, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.00589872244745, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.000615633151028, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.00290380162187, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.000114265829325, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.000565168214962, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.000789216835983, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.00413721986115, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(6.77537173033e-08, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(3.77651304007e-07, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.000478343747091, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.00281916023232, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.000978335738182, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.00617696810514, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.00102204689756, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.0069464542903, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.000508224184159, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.0036957343109, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.000524436822161, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.00415134476498, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(2.65674752882e-05, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.000230673758779, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(3.54821968358e-05, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.000335898716003, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.000183268348337, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.00193877634592, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.0005744821392, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.00688455393538, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(5.98068290856e-05, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.000808617565781, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.000123083344079, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.00195635366254, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(9.81068733381e-05, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.00189093407243, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.000332527211867, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.00783579517156, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-9.20054735616e-05, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.00292766164057, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.000105902690848, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.00518541317433, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(9.87050407275e-06, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.000897643680219, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.00780914071947, samples[301], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

@end
