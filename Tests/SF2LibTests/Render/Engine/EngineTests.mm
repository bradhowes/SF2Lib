// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <array>
#include <cmath>
#include <iostream>
#include <numeric>
#include <vector>

#include <XCTest/XCTest.h>

#include "DSPHeaders/Types.hpp"

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

#include "SF2Lib/Configuration.hpp"
#include "SF2Util/Base64.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"

using namespace SF2;
using namespace SF2::Entity::Generator;
using namespace SF2::Render::Engine;

/// Render one note with an optional raw MIDI pitch-bend message sent before the note-on. Returns the left channel of
/// the dry bus.
static std::vector<AUValue> renderNoteAfterPitchBend(const std::string& path, const std::array<uint8_t, 3>* bend)
{
  auto harness{TestEngineHarness{48000.0}};
  harness.load(path, 0);
  auto mixer{harness.createMixer(0.25)};
  if (bend != nullptr) harness.sendRaw(*bend);
  harness.sendNoteOn(60, 100);
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + harness.bufferFrameCount());
}

/// Render one note with the volume envelope forced to (near) instant delay/attack/hold/decay and the given sustain level
/// in centibels. Returns the left channel of the dry bus.
static std::vector<AUValue> renderNoteWithVolumeSustain(const std::string& path, int sustainCentibels)
{
  auto harness{TestEngineHarness{48000.0}};
  harness.load(path, 0);
  harness.setParameter(Index::delayVolumeEnvelope, AUValue(-12'000));
  harness.setParameter(Index::attackVolumeEnvelope, AUValue(-12'000));
  harness.setParameter(Index::holdVolumeEnvelope, AUValue(-12'000));
  harness.setParameter(Index::decayVolumeEnvelope, AUValue(-12'000));
  harness.setParameter(Index::sustainVolumeEnvelope, AUValue(sustainCentibels));
  auto mixer{harness.createMixer(0.25)};
  harness.sendNoteOn(60, 100);
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + harness.bufferFrameCount());
}

/// Render one 0.25 s note of preset 0 of the given file after applying the generator overrides. Returns the left
/// channel of the dry bus.
static std::vector<AUValue> renderNoteWithGenerators(const std::string& path,
                                                     const std::vector<std::pair<Index, AUValue>>& generators)
{
  auto harness{TestEngineHarness{48000.0}};
  harness.load(path, 0);
  for (const auto& [index, value] : generators) harness.setParameter(index, value);
  auto mixer{harness.createMixer(0.25)};
  harness.sendNoteOn(60, 127);
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + harness.bufferFrameCount());
}

/// Mod envelope that jumps straight to full scale and stays there.
static const std::vector<std::pair<Index, AUValue>> instantModEnvelope{
  {Index::delayModulatorEnvelope, -12'000}, {Index::attackModulatorEnvelope, -12'000},
  {Index::holdModulatorEnvelope, -12'000}, {Index::decayModulatorEnvelope, -12'000},
  {Index::sustainModulatorEnvelope, 0}};

/// A 3-byte MIDI message and how long to render (in seconds) after sending it.
using TimedMIDIEvents = std::vector<std::pair<int, std::array<uint8_t, 3>>>;

/// Render 1 second of preset 0 of the given file. Each MIDI message is sent and then followed by its render duration;
/// whatever remains of the second is rendered after the last one. Returns the left channel of the dry bus.
static std::vector<AUValue> renderMIDISequence(const std::string& path, const TimedMIDIEvents& events)
{
  auto harness{TestEngineHarness{48000.0}};
  harness.load(path, 0);
  auto mixer{harness.createMixer(1.0)};
  for (const auto& [blocks, bytes] : events) {
    harness.sendRaw(bytes);
    harness.renderMaxFramesCount(mixer, blocks);
  }
  harness.renderToEnd(mixer);

  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + harness.bufferFrameCount());
}

static std::array<uint8_t, 3> noteOnBytes(uint8_t key) { return {0x90, key, 100}; }
static std::array<uint8_t, 3> noteOffBytes(uint8_t key) { return {0x80, key, 0}; }
static std::array<uint8_t, 3> sustainBytes(bool down) { return {0xB0, 64, uint8_t(down ? 127 : 0)}; }
static std::array<uint8_t, 3> sostenutoBytes(bool down) { return {0xB0, 66, uint8_t(down ? 127 : 0)}; }

/// RMS of samples in [begin, end)
static double rms(const std::vector<AUValue>& samples, size_t begin, size_t end)
{
  double sum = 0.0;
  for (auto index = begin; index < end; ++index) sum += double(samples[index]) * double(samples[index]);
  return std::sqrt(sum / double(end - begin));
}

@interface EngineTests : SamplePlayingTestCase
@end

@implementation EngineTests

- (void)setUp {
  [super setUp];
  self.playAudio = true;
}

- (void)testInit {
  Engine engine(44100.0, 32, -1.0);
  XCTAssertEqual(engine.voiceCountLimit(), size_t(32));
  XCTAssertEqual(engine.activeVoiceCount(), size_t(0));
  XCTAssertTrue(engine.polyphonicModeEnabled());
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
  XCTAssertFalse(engine.portamentoModeEnabled());
  XCTAssertEqual(size_t(100), engine.portamentoRate());
  XCTAssertTrue(engine.retriggerModeEnabled());
  XCTAssertEqual(traits::minLastLoadFinished, engine.lastLoadFinishedCounter());
  XCTAssertEqual(engine.activeBankIndex(), -1);
  XCTAssertEqual(engine.activeProgramIndex(), -1);
  XCTAssertEqual(engine.activePresetIndex(), -1);
}

- (void)testPortamento {
  auto harness{TestEngineHarness{48000.0, 32}};
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
  auto harness{TestEngineHarness{48000.0, 32}};
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
  auto harness{TestEngineHarness{48000.0, 32}};
  auto& engine{harness.engine()};

  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());

  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 1.0);
  XCTAssertTrue(engine.oneVoicePerKeyModeEnabled());

  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 0.0);
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
}

- (void)testRetriggering {
  auto harness{TestEngineHarness{48000.0, 32}};
  auto& engine{harness.engine()};

  XCTAssertTrue(engine.retriggerModeEnabled());

  harness.setParameter(ParameterAddress::retriggerModeEnabled, 0.0);
  XCTAssertFalse(engine.retriggerModeEnabled());

  harness.setParameter(ParameterAddress::retriggerModeEnabled, 1.0);
  XCTAssertTrue(engine.retriggerModeEnabled());
}

- (void)testLoad {
  auto harness{TestEngineHarness{48000.0, 32}};
  auto& engine{harness.engine()};
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0, 0.0005);

  harness.load(self.contexts->context0.path(), 0);
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0001, 0.0005);

  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqual(engine.presetCount(), size_t(235));
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0002, 0.0005);
  XCTAssertEqual(engine.activeBankIndex(), 0);
  XCTAssertEqual(engine.activeProgramIndex(), 0);
  XCTAssertEqual(engine.activePresetIndex(), 0);

  XCTAssertEqual(harness.load(self.contexts->context0.path(), 123), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqual(engine.activeBankIndex(), 0);
  XCTAssertEqual(engine.activeProgramIndex(), 123);
  XCTAssertEqual(engine.activePresetIndex(), 123);

  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual(harness.load(self.contexts->context1.path(), 10000), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0003, 0.0005);
  XCTAssertEqual(engine.activeBankIndex(), -1);
  XCTAssertEqual(engine.activeProgramIndex(), -1);

  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual(harness.load(self.contexts->context2.path(), 0), SF2::IO::File::LoadResponse::ok);
  XCTAssertEqualWithAccuracy(engine.lastLoadFinishedCounter(), 0.0004, 0.0005);
  XCTAssertEqual(engine.activeBankIndex(), 0);
  XCTAssertEqual(engine.activeProgramIndex(), 1);
  XCTAssertEqual(engine.activePresetIndex(), 0);
}

- (void)testUsePresetByIndex {
  auto harness{TestEngineHarness{48000.0, 32}};
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

//- (void)testRolandPianoChordRenderLinear {
//  auto harness{TestEngineHarness{48000.0, 32, SF2::Render::Voice::Sample::Interpolator::linear}};
//  auto& engine{harness.engine()};
//  harness.load(self.contexts->context2.path(), 0);
//
//  int cycles = 5;
//  auto mixer{harness.createMixer(12.0)};
//  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
//
//  std::vector<AUValue> samples;
//
//  auto playChord = [&](uint8_t note1, uint8_t note2, uint8_t note3, bool sustain) {
//    harness.renderMaxFramesCount(mixer);
//    harness.sendNoteOn(note1);
//    harness.sendNoteOn(note2);
//    harness.sendNoteOn(note3);
//    harness.renderForDuration(mixer, 0.25);
//    if (!sustain) {
//      harness.sendNoteOff(note1);
//      harness.sendNoteOff(note2);
//      harness.sendNoteOff(note3);
//    }
//  };
//
//  for (auto count = 0; count < cycles; ++count) {
//    playChord(60, 64, 67, false);
//    samples.push_back(harness.lastDrySample());
//    playChord(60, 65, 69, false);
//    samples.push_back(harness.lastDrySample());
//    playChord(60, 64, 67, false);
//    samples.push_back(harness.lastDrySample());
//    playChord(59, 62, 67, false);
//    samples.push_back(harness.lastDrySample());
//    playChord(60, 64, 67, count == cycles - 1);
//    samples.push_back(harness.lastDrySample());
//  }
//
//  XCTAssertEqual(size_t(54), engine.activeVoiceCount());
//  harness.renderToEnd(mixer);
//  samples.push_back(harness.lastDrySample());
//  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
//
//  [self dumpSamples: samples];
//
//  XCTAssertEqualWithAccuracy(0.0484130382538, samples[0], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0209413710982, samples[1], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0479802936316, samples[2], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0732565447688, samples[3], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0271318107843, samples[4], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.04047684744, samples[5], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0161847602576, samples[6], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0476960875094, samples[7], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0730952322483, samples[8], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0271220896393, samples[9], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0405118837953, samples[10], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0161952637136, samples[11], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0476932115853, samples[12], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0730952322483, samples[13], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0271220896393, samples[14], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0405118837953, samples[15], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0161952637136, samples[16], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0476932115853, samples[17], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0730952322483, samples[18], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0271220896393, samples[19], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0405118837953, samples[20], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0161952637136, samples[21], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0476932115853, samples[22], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0730952322483, samples[23], self.epsilon);
//  XCTAssertEqualWithAccuracy(0.0271220896393, samples[24], self.epsilon);
//  XCTAssertEqualWithAccuracy(0, samples[25], self.epsilon);
//
//  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
//}

- (void)testRolandPianoChordRenderCubic4thOrder {
  auto harness{TestEngineHarness{48000.0, 32}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  int cycles = 5;
  auto mixer{harness.createMixer(12.0)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  std::vector<AUValue> samples;

  auto playChord = [&](uint8_t note1, uint8_t note2, uint8_t note3, bool sustain) {
    harness.renderMaxFramesCount(mixer);
    harness.sendNoteOn(note1);
    harness.sendNoteOn(note2);
    harness.sendNoteOn(note3);
    harness.renderForDuration(mixer, 0.25);
    if (!sustain) {
      harness.sendNoteOff(note1);
      harness.sendNoteOff(note2);
      harness.sendNoteOff(note3);
    }
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

  XCTAssertEqual(size_t(54), engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self dumpSamples: samples];

  auto epsilon = self.epsilon;
  XCTAssertEqualWithAccuracy(0.0484381914139, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0209572464228, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0480050891638, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0733431056142, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0271453429013, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0404991656542, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0161975510418, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0477207191288, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0731818154454, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0271355789155, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0405342169106, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0162080544978, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0477178432047, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0731818154454, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0271355789155, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0405342169106, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0162080544978, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0477178432047, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0731818154454, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0271355789155, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0405342169106, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0162080544978, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0477178432047, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0731818154454, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0271355789155, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[25], epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
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
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.renderForDuration(mixer, 0.5);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::programChange);
  midiEvent.data[1] = 23;
  midiEvent.length = 2;

  engine.doMIDIEvent(midiEvent);
  harness.drainWorkQueue(); // the program change loads on the work queue
  name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
  NSLog(@"name: |%@|", name);
  XCTAssertTrue([name isEqualToString:@"Bandoneon"]);
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::noteOn);
  midiEvent.data[1] = 0x40;
  midiEvent.data[2] = 0x7F;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.00132336514071, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0147862089798, samples[1], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testYamahaPianoChordRender {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 3;
  auto mixer{harness.createMixer(seconds)};

  // Set NPRN state so that voices send 20% output to the chorus channel
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnMSB, 120);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Index::chorusEffectSend));
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 65);

  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  auto playChord = [&](uint8_t note1, uint8_t note2, uint8_t note3, bool sustain) {
    harness.renderForDuration(mixer, 0.1);
    harness.sendNoteOn(note1);
    harness.sendNoteOn(note2);
    harness.sendNoteOn(note3);
    harness.renderForDuration(mixer, 0.5);
    if (!sustain) {
      harness.sendNoteOff(note1);
      harness.sendNoteOff(note2);
      harness.sendNoteOff(note3);
    }
  };

  playChord(60, 64, 67, false);
  playChord(60, 65, 69, false);
  playChord(60, 64, 67, false);
  playChord(59, 62, 67, false);
  playChord(60, 64, 67, true);

  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(3), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
  [self playSamples: harness.chorusBuffer() count: harness.bufferFrameCount()];
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
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::noteOn);
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
  harness.renderForDuration(mixer, 0.2);

  // Note 1 off
  midiEvent.data[0] = 0x80;
  midiEvent.data[1] = 0x40;
  midiEvent.length = 2;
  engine.doMIDIEvent(midiEvent);

  // Render another 20%
  harness.renderForDuration(mixer, 0.2);

  // Note 2 off
  midiEvent.data[1] = 0x44;
  engine.doMIDIEvent(midiEvent);

  // Render rest
  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineMIDINoteRandomNoteOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  harness.sendNoteOn(40);
  harness.renderForDuration(mixer, 0.4);

  harness.sendNoteOff(40);
  harness.sendNoteOff(40);
  harness.renderForDuration(mixer, 0.4);

  harness.sendNoteOn(41);
  harness.sendNoteOn(42);
  harness.renderForDuration(mixer, 0.4);

  harness.sendNoteOff(41);
  harness.sendNoteOff(41);
  harness.renderForDuration(mixer, 0.4);

  harness.sendNoteOff(42);
  harness.sendNoteOff(42);
  harness.sendNoteOff(42);

  harness.renderToEnd(mixer);

  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineMIDINoteOnAsNoteOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 1;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  harness.sendNoteOn(40);
  harness.renderForDuration(mixer, 0.5);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  harness.sendNoteOn(40, 0);
  harness.renderToEnd(mixer);

  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
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
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::noteOn);
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

  harness.renderForDuration(mixer, 0.4);
  samples.push_back(harness.lastDrySample());

  // Pitch wheel all the way up
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::pitchBend);
  midiEvent.data[1] = 127;
  midiEvent.data[2] = 127;
  engine.doMIDIEvent(midiEvent);
  harness.renderForDuration(mixer, 0.4);
  samples.push_back(harness.lastDrySample());

  // Pitch wheel all the way down
  midiEvent.data[1] = 0;
  midiEvent.data[2] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderForDuration(mixer, 0.4);
  samples.push_back(harness.lastDrySample());

  // Pitch wheel at center
  midiEvent.data[1] = 0;
  midiEvent.data[2] = 0x40;
  engine.doMIDIEvent(midiEvent);
  harness.renderForDuration(mixer, 0.4);
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.194214180112, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0128473900259, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00808507762849, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0160565469414, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00837563537061, samples[4], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineExcludeClassNoteTermination
{
  // SF2.01 8.1.2 #57: a new note with the same exclusiveClass "rapidly terminates" a sounding one. Use a ~5 ms release
  // rather than a hard cut: the old voice must still be fading after 1 ms and gone after 6 ms. It actually stops after
  // about 2 ms, because its gain (which includes the velocity attenuation) drops below the -80 dB cut-off early.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context1.path(), 260);
  auto mixer{harness.createMixer(1.5)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  auto note = 46;
  harness.sendNoteOn(note);
  harness.renderForDuration(mixer, 0.1);  // let the first note sound before it is cut off
  harness.sendNoteOn(note);
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());
  harness.renderForDuration(mixer, 0.001);
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());  // still fading (used to be a hard cut)
  harness.renderForDuration(mixer, 0.005);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testExclusiveClassChokesReleasingNote
{
  // A note that has been released and is still ringing out is also "sounding" (8.1.2 #57), so a new note in the same
  // class cuts it off. Previously a voice already in its release phase was skipped.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context1.path(), 260);
  auto mixer{harness.createMixer(1.0)};

  auto note = 46;
  harness.sendNoteOn(note);
  harness.renderForDuration(mixer, 0.1);
  harness.sendNoteOff(note);
  harness.renderForDuration(mixer, 0.01);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());  // ringing out in its release phase
  harness.sendNoteOn(note);
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());
  harness.renderForDuration(mixer, 0.001);
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());
  harness.renderForDuration(mixer, 0.005);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
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
  harness.renderForDuration(mixer, 0.4);
  samples.push_back(harness.lastDrySample());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::channelPressure);
  midiEvent.length = 2;

  midiEvent.data[1] = 127;
  engine.doMIDIEvent(midiEvent);
  harness.renderForDuration(mixer, 0.4);
  samples.push_back(harness.lastDrySample());

  midiEvent.data[1] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00927150808275, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0303932055831, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00281225889921, samples[2], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
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
  harness.renderForDuration(mixer, 0.1);
  samples.push_back(harness.lastDrySample());

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::keyPressure);
  midiEvent.data[1] = 60;
  midiEvent.length = 3;

  for (auto count = 1; count <= 4; ++count) {
    midiEvent.data[2] = 127;
    engine.doMIDIEvent(midiEvent);
    harness.renderForDuration(mixer, 0.1);
    samples.push_back(harness.lastDrySample());

    midiEvent.data[2] = 32;
    engine.doMIDIEvent(midiEvent);
    harness.renderForDuration(mixer, 0.1);
    samples.push_back(harness.lastDrySample());
  }

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0137237422168, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0827673971653, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0523559898138, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.052486486733, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0136061022058, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0617988854647, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0901300311089, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0392570383847, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0674479976296, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0153729561716, samples[9], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
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
  harness.renderForDuration(mixer, 0.2);
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sustainPedalActive);

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = DSPHeaders::valueOf(MIDI::ControlChange::sustainSwitch);
  midiEvent.data[2] = 64;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertTrue(engine.channelState().pedalState().sustainPedalActive);

  harness.renderForDuration(mixer, 0.2);
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderForDuration(mixer, 0.2);
  XCTAssertTrue(engine.channelState().pedalState().sustainPedalActive);
  XCTAssertEqual(size_t(3), engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  midiEvent.data[2] = 0;
  engine.doMIDIEvent(midiEvent);
  harness.renderForDuration(mixer, 0.2);
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sustainPedalActive);

  harness.sendNoteOn(72, 127);
  harness.sendNoteOn(76, 127);
  harness.sendNoteOn(79, 127);
  harness.renderForDuration(mixer, 0.2);
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderForDuration(mixer, 0.2);
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.067690089345, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0105933696032, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0229632202536, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00023230604711, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0681528672576, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00174471200444, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[6], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
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
  harness.renderForDuration(mixer, 0.1);
  samples.push_back(harness.lastDrySample());
  XCTAssertFalse(engine.channelState().pedalState().sostenutoPedalActive);

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = DSPHeaders::valueOf(MIDI::ControlChange::sostenutoSwitch);
  midiEvent.data[2] = 64;
  midiEvent.length = 3;

  engine.doMIDIEvent(midiEvent);
  XCTAssertTrue(engine.channelState().pedalState().sostenutoPedalActive);

  harness.renderForDuration(mixer, 0.1);
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOff(72);
  harness.sendNoteOff(76);
  harness.sendNoteOff(79);
  harness.renderForDuration(mixer, 0.3);
  XCTAssertTrue(engine.channelState().pedalState().sostenutoPedalActive);
  XCTAssertEqual(size_t(3), engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  harness.sendNoteOn(74, 127);
  harness.sendNoteOn(78, 127);
  harness.sendNoteOn(81, 127);
  harness.renderForDuration(mixer, 0.2);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(6), engine.activeVoiceCount());

  harness.sendNoteOff(74);
  harness.sendNoteOff(88);
  harness.sendNoteOff(81);
  harness.renderForDuration(mixer, 0.2);
  XCTAssertEqual(size_t(6), engine.activeVoiceCount());
  samples.push_back(harness.lastDrySample());

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(4), engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0724020972848, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.067690089345, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0276621151716, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0541961565614, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00824993383139, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00429384317249, samples[5], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineMIDIControlChangeCC10ForPanning
{
  auto blah = [NSProcessInfo.processInfo.environment valueForKey:@"SNAPSHOT_ARTIFACTS"];
  std::cout << "SNAPSHOT_ARTIFACTS: " << blah << "\n";
  // return;

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
  harness.renderMaxFramesCount(mixer);
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = 10;
  midiEvent.length = 3;

  // Pan left
  auto steps = harness.engine().sampleRate() / harness.maxFramesToRender();
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = uint8_t(64 - (step / steps * 64));
    engine.doMIDIEvent(midiEvent);
    harness.renderMaxFramesCount(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = uint8_t(64 - (step / steps * 64));
    engine.doMIDIEvent(midiEvent);
    harness.renderMaxFramesCount(mixer);
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = uint8_t(64 + (step / steps * 63));
    engine.doMIDIEvent(midiEvent);
    harness.renderMaxFramesCount(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = uint8_t(64 + (step / steps * 63));
    engine.doMIDIEvent(midiEvent);
    harness.renderMaxFramesCount(mixer);
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.0135538503528, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0135538503528, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.023015787825, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022444486618, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0993282496929, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0944568738341, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00983873941004, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00915232487023, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0281694233418, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0262041445822, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00851811468601, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00772646442056, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(0.026532990858, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(0.023466154933, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0455828011036, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.040314078331, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0495309978724, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0427087694407, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0086662909016, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00728478096426, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0155516322702, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0130725130439, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0169815290719, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0139140766114, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0334162265062, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.02677144669, samples[25], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0137008279562, samples[26], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0109764328226, samples[27], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0317801013589, samples[28], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.024811476469, samples[29], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0336596369743, samples[30], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0256046578288, samples[31], self.epsilon);
  XCTAssertEqualWithAccuracy(0.047669492662, samples[32], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0362618565559, samples[33], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0115094017237, samples[34], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00852894876152, samples[35], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0190761648118, samples[36], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0137682873756, samples[37], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00849005859345, samples[38], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00612772861496, samples[39], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0260655190796, samples[40], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0183803886175, samples[41], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0367697998881, samples[42], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0252428501844, samples[43], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0309207625687, samples[44], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0206605941057, samples[45], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0621347017586, samples[46], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0415170788765, samples[47], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0124589418992, samples[48], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00810020789504, samples[49], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.02516371198, samples[50], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0159139856696, samples[51], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00565683934838, samples[52], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00357748754323, samples[53], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0510728359222, samples[54], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0315186083317, samples[55], self.epsilon);
  XCTAssertEqualWithAccuracy(0.031502649188, samples[56], self.epsilon);
  XCTAssertEqualWithAccuracy(0.018898781389, samples[57], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0625081956387, samples[58], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0374993495643, samples[59], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0258728526533, samples[60], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0150825493038, samples[61], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0126130618155, samples[62], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00714194076136, samples[63], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0285283215344, samples[64], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0161536969244, samples[65], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0243992805481, samples[66], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0134136183187, samples[67], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0262971464545, samples[68], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0140295755118, samples[69], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0406875684857, samples[70], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0217068903148, samples[71], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0325696989894, samples[72], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0169186033309, samples[73], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0367823913693, samples[74], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0185237526894, samples[75], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00431000534445, samples[76], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00217053527012, samples[77], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0373271331191, samples[78], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0182137247175, samples[79], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0377689525485, samples[80], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.017845235765, samples[81], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0932796448469, samples[82], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0440731719136, samples[83], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0289921760559, samples[84], self.epsilon);
  XCTAssertEqualWithAccuracy(0.013255296275, samples[85], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00868183374405, samples[86], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00385451340117, samples[87], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0160846654326, samples[88], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00690054427832, samples[89], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0211534723639, samples[90], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00907513126731, samples[91], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00177351431921, samples[92], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000734613509849, samples[93], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.016932727769, samples[94], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00676575256512, samples[95], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0344342887402, samples[96], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0137587934732, samples[97], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0767858624458, samples[98], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0295676272362, samples[99], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00301125086844, samples[100], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00112166907638, samples[101], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0390997156501, samples[102], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0145643651485, samples[103], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0259139947593, samples[104], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00928365625441, samples[105], self.epsilon);
  XCTAssertEqualWithAccuracy(0.018284836784, samples[106], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0062924050726, samples[107], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0292324535549, samples[108], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0100598344579, samples[109], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0502079427242, samples[110], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0165755301714, samples[111], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0390180684626, samples[112], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0123397950083, samples[113], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0134628117085, samples[114], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00425772834569, samples[115], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00279863597825, samples[116], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000846557319164, samples[117], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0479875206947, samples[118], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0139416623861, samples[119], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0527750700712, samples[120], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0153325749561, samples[121], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0123098911718, samples[122], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0034092082642, samples[123], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0656438395381, samples[124], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0172948297113, samples[125], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00572658516467, samples[126], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00143204536289, samples[127], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0564814284444, samples[128], self.epsilon);
  XCTAssertEqualWithAccuracy(0.014124291949, samples[129], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0416537746787, samples[130], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0098618902266, samples[131], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0265712700784, samples[132], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00598322227597, samples[133], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0367251113057, samples[134], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00826962664723, samples[135], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0273687168956, samples[136], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00580242462456, samples[137], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0243961829692, samples[138], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00485270284116, samples[139], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00342093780637, samples[140], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000680465716869, samples[141], self.epsilon);
  XCTAssertEqualWithAccuracy(0.053342834115, samples[142], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00991540309042, samples[143], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0222779586911, samples[144], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00385207566433, samples[145], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0372375026345, samples[146], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00643872655928, samples[147], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0605808272958, samples[148], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00979025289416, samples[149], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00648926943541, samples[150], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00096519687213, samples[151], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00160829629749, samples[152], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00023921369575, samples[153], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0585058741271, samples[154], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00795189943165, samples[155], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00841745082289, samples[156], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00103651580866, samples[157], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0474978648126, samples[158], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00584883522242, samples[159], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0281610861421, samples[160], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00310901296325, samples[161], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0753212720156, samples[162], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00735877128318, samples[163], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0163871254772, samples[164], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00160099670757, samples[165], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0226689837873, samples[166], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00196334673092, samples[167], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0944949835539, samples[168], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00698902411386, samples[169], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0155733153224, samples[170], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000955233233981, samples[171], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0168960336596, samples[172], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0010363656329, samples[173], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0335486680269, samples[174], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00163493445143, samples[175], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0262750573456, samples[176], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000949686917011, samples[177], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0414986908436, samples[178], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00149993074592, samples[179], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0464344248176, samples[180], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0011672701221, samples[181], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0173303447664, samples[182], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000217790962779, samples[183], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0529106035829, samples[184], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000664929219056, samples[185], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0105873970315, samples[186], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[187], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00965521112084, samples[188], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00965521112084, samples[189], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0164015125483, samples[190], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0168189965189, samples[191], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0438434891403, samples[192], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.046104606241, samples[193], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0188877061009, samples[194], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0198617931455, samples[195], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0104400878772, samples[196], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0112230852246, samples[197], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00552543578669, samples[198], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00609156955034, samples[199], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0197950992733, samples[200], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0218233019114, samples[201], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00846769381315, samples[202], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00957435276359, samples[203], self.epsilon);
  XCTAssertEqualWithAccuracy(0.045579791069, samples[204], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0528606399894, samples[205], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0156519189477, samples[206], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0181521289051, samples[207], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0530915744603, samples[208], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0631600543857, samples[209], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00135794468224, samples[210], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00165731459856, samples[211], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00240425206721, samples[212], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00293428637087, samples[213], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0120043139905, samples[214], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0149838309735, samples[215], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0229217298329, samples[216], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0293595902622, samples[217], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0122893881053, samples[218], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0157410204411, samples[219], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0534377321601, samples[220], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0702487379313, samples[221], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0129088750109, samples[222], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0174198988825, samples[223], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0212822593749, samples[224], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0287193693221, samples[225], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0141343530267, samples[226], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0195833537728, samples[227], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00675640814006, samples[228], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00958137027919, samples[229], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000725075602531, samples[230], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00102824531496, samples[231], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0442422181368, samples[232], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.064445078373, samples[233], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0134706106037, samples[234], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0201601907611, samples[235], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000964157050475, samples[236], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00144296279177, samples[237], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0148735139519, samples[238], self.epsilon);
  XCTAssertEqualWithAccuracy(0.02287697047, samples[239], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0258111730218, samples[240], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0408134646714, samples[241], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0250775068998, samples[242], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0396533682942, samples[243], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0242349412292, samples[244], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0392703637481, samples[245], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0345216915011, samples[246], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0575446970761, samples[247], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00459812860936, samples[248], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00766468513757, samples[249], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0135263502598, samples[250], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0232033208013, samples[251], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0486874729395, samples[252], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0859847664833, samples[253], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0131186107174, samples[254], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0231681875885, samples[255], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0153835304081, samples[256], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0279825367033, samples[257], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00410758610815, samples[258], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00769929029047, samples[259], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0115637928247, samples[260], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0216752663255, samples[261], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00865432526916, samples[262], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0166602879763, samples[263], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0226874649525, samples[264], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0450502261519, samples[265], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00414078915492, samples[266], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00822231546044, samples[267], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0107404030859, samples[268], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0220113396645, samples[269], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0243719089776, samples[270], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0515824705362, samples[271], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0179420169443, samples[272], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0379737839103, samples[273], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0208282507956, samples[274], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0455558560789, samples[275], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0155797144398, samples[276], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0350914634764, samples[277], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0111456122249, samples[278], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0251041706651, samples[279], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00468253903091, samples[280], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0109146581963, samples[281], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00547255342826, samples[282], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0132119124755, samples[283], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00541770365089, samples[284], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0130794951692, samples[285], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0255557894707, samples[286], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0639587715268, samples[287], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00798250921071, samples[288], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0207302346826, samples[289], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00937017798424, samples[290], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0243339501321, samples[291], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0193960778415, samples[292], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0520710088313, samples[293], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0105225713924, samples[294], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.029372246936, samples[295], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0024051181972, samples[296], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0067135412246, samples[297], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0199151393026, samples[298], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0578705668449, samples[299], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00165015342645, samples[300], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00499838031828, samples[301], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00493685854599, samples[302], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0149539401755, samples[303], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0119058834389, samples[304], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0376460514963, samples[305], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00709014199674, samples[306], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0234393235296, samples[307], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00785748381168, samples[308], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0259760785848, samples[309], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00700197834522, samples[310], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0241009704769, samples[311], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0106903836131, samples[312], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0386005938053, samples[313], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00321510829963, samples[314], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0122031867504, samples[315], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000237237662077, samples[316], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000900454819202, samples[317], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0146257728338, samples[318], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0584867931902, samples[319], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0118421046063, samples[320], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0500176399946, samples[321], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00472741341218, samples[322], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0199672318995, samples[323], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00623971829191, samples[324], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0277103632689, samples[325], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000937281642109, samples[326], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00442094169557, samples[327], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00839370023459, samples[328], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0395911671221, samples[329], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00877901073545, samples[330], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0441350638866, samples[331], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00372005114332, samples[332], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0200131125748, samples[333], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00697038276121, samples[334], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.037499230355, samples[335], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00624635489658, samples[336], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0361249446869, samples[337], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0101739503443, samples[338], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.062955096364, samples[339], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00041584786959, samples[340], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0025732126087, samples[341], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00983748864383, samples[342], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0661400035024, samples[343], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000326367211528, samples[344], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00240123644471, samples[345], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00630188547075, samples[346], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0463659390807, samples[347], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00244199391454, samples[348], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0198312122375, samples[349], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00178268412128, samples[350], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0161473490298, samples[351], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000667821324896, samples[352], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00604904908687, samples[353], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00527598476037, samples[354], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0540027506649, samples[355], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00297225639224, samples[356], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0343179479241, samples[357], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00406063068658, samples[358], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0468844175339, samples[359], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00274339364842, samples[360], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0370920039713, samples[361], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000521004432812, samples[362], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00849401764572, samples[363], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00130938575603, samples[364], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0213471222669, samples[365], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000537295360118, samples[366], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0110252425075, samples[367], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00287931039929, samples[368], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0796620845795, samples[369], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00201365118846, samples[370], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0557118356228, samples[371], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00068764667958, samples[372], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0273548327386, samples[373], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
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
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::reset);
  midiEvent.length = 1;
  engine.doMIDIEvent(midiEvent);

  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineMIDILoadPath {
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

  // Post a sentinal work item that will tell us when the Engine's work queue is empty.
  auto exp = [self expectationWithDescription:@"empty queue"];
  harness.postWorkItem(^{ [exp fulfill]; });
  [self waitForExpectations:@[exp]];

  std::cout << engine.activePresetName() << '\n';

  XCTAssertEqual(0, engine.presetChangesPending());
  XCTAssertEqual(std::string("SFX"), engine.activePresetName());
}

- (void)testEngineDirectLoadPath {
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
  engine.loadFileAndPreset(tmp, 234);

  std::cout << engine.activePresetName() << '\n';

  XCTAssertEqual(0, engine.presetChangesPending());
  XCTAssertEqual(std::string("SFX"), engine.activePresetName());
}

- (void)testEngineMIDILoadPathEmpty {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);
  XCTAssertEqual(std::string("Piano 1"), engine.activePresetName());

  auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
  auto payload = engine.createLoadFileUsePresetPayload("", 1, overrides);
  harness.sendRaw(payload);

  payload = engine.createLoadFileUsePresetPayload("", 2, overrides);
  harness.sendRaw(payload);

  payload = engine.createLoadFileUsePresetPayload("", 3, overrides);
  harness.sendRaw(payload);

  payload = engine.createLoadFileUsePresetPayload("", 4, overrides);
  harness.sendRaw(payload);

  // Post a sentinal work item that will tell us when the Engine's work queue is empty.
  auto exp = [self expectationWithDescription:@"empty queue"];
  harness.postWorkItem(^{ [exp fulfill]; });
  [self waitForExpectations:@[exp]];

  XCTAssertEqual(0, engine.presetChangesPending());
  XCTAssertEqual(std::string("E.Piano 1"), engine.activePresetName());
}

- (void)testEngineMIDILoadBookmark {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());

  const NSURL* url = self.contexts->context0.url();
  NSLog(@"URL: %@", url);

  auto didStart = [url startAccessingSecurityScopedResource];
  NSError* error = nil;
  NSData* bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                              includingResourceValuesForKeys:nil
                                               relativeToURL:nil
                                                       error:&error];
  if (didStart) { [url stopAccessingSecurityScopedResource]; }

  auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
  overrides.emplace_back(123, 456);
  auto payload = engine.createLoadBookmarkUsePresetPayload(bookmark, 234, overrides);
  harness.sendRaw(payload);

  // Post a sentinal work item that will tell us when the Engine's work queue is empty.
  auto exp = [self expectationWithDescription:@"empty queue"];
  harness.postWorkItem(^{ [exp fulfill]; });
  [self waitForExpectations:@[exp]];

  XCTAssertEqual(0, engine.presetChangesPending());
  XCTAssertEqual(std::string("SFX"), engine.activePresetName());
}

- (void)testEngineDirectLoadBookmark {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());

  const NSURL* url = self.contexts->context0.url();
  NSLog(@"URL: %@", url);

  auto didStart = [url startAccessingSecurityScopedResource];
  NSError* error = nil;
  NSData* bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                   includingResourceValuesForKeys:nil
                                    relativeToURL:nil
                                            error:&error];
  if (didStart) { [url stopAccessingSecurityScopedResource]; }

  engine.loadBookmarkAndPreset(bookmark, 234);

  XCTAssertEqual(0, engine.presetChangesPending());
  XCTAssertEqual(std::string("SFX"), engine.activePresetName());
}

- (void)testEngineMIDILoadBookmarkMultiple {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());

  // Enqueue three load operations to ensure that they run sequentially and only the last one matters.
  const NSURL* url = self.contexts->context0.url();

  auto didStart = [url startAccessingSecurityScopedResource];
  NSError* error = nil;
  NSData* bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                   includingResourceValuesForKeys:nil
                                    relativeToURL:nil
                                            error:&error];
  if (didStart) { [url stopAccessingSecurityScopedResource]; }

  auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
  auto payload = engine.createLoadBookmarkUsePresetPayload(bookmark, 234, overrides);
  harness.sendRaw(payload);

  // Start a note. Should not be playing at end of test.
  harness.sendNoteOn(64);

  url = self.contexts->context1.url();
  didStart = [url startAccessingSecurityScopedResource];
  bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
           includingResourceValuesForKeys:nil
                            relativeToURL:nil
                                    error:&error];
  payload = engine.createLoadBookmarkUsePresetPayload(bookmark, 0, overrides);
  harness.sendRaw(payload);

  url = self.contexts->context2.url();
  didStart = [url startAccessingSecurityScopedResource];
  bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
           includingResourceValuesForKeys:nil
                            relativeToURL:nil
                                    error:&error];
  payload = engine.createLoadBookmarkUsePresetPayload(bookmark, 0, overrides);
  harness.sendRaw(payload);

  // Post a sentinal work item that will tell us when the Engine's work queue is empty.
  auto exp = [self expectationWithDescription:@"empty queue"];
  harness.postWorkItem(^{ [exp fulfill]; });
  [self waitForExpectations:@[exp]];

  XCTAssertEqual(0, engine.presetChangesPending());
  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());
  XCTAssertEqual(size_t(1), engine.presetCount());
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineRenderStopFlushesPendingQueue {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context2.path(), 0);

  XCTAssertEqual(std::string("Nice Piano"), engine.activePresetName());

  // Enqueue three load operations to ensure that they run sequentially and only the last one matters.
  const NSURL* url = self.contexts->context0.url();

  auto didStart = [url startAccessingSecurityScopedResource];
  NSError* error = nil;
  NSData* bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                   includingResourceValuesForKeys:nil
                                    relativeToURL:nil
                                            error:&error];
  if (didStart) { [url stopAccessingSecurityScopedResource]; }

  auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
  auto payload = engine.createLoadBookmarkUsePresetPayload(bookmark, 234, overrides);
  harness.sendRaw(payload);

  // Start a note. Should not be playing at end of test.
  harness.sendNoteOn(64);

  url = self.contexts->context1.url();
  didStart = [url startAccessingSecurityScopedResource];
  bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
           includingResourceValuesForKeys:nil
                            relativeToURL:nil
                                    error:&error];
  payload = engine.createLoadBookmarkUsePresetPayload(bookmark, 0, overrides);
  harness.sendRaw(payload);

  url = self.contexts->context2.url();
  didStart = [url startAccessingSecurityScopedResource];
  bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
           includingResourceValuesForKeys:nil
                            relativeToURL:nil
                                    error:&error];
  payload = engine.createLoadBookmarkUsePresetPayload(bookmark, 0, overrides);
  harness.sendRaw(payload);

  // Post a sentinal work item that will tell us when the Engine's work queue is empty.
  auto exp = [self expectationWithDescription:@"empty queue"];
  harness.postWorkItem(^{ [exp fulfill]; });

  XCTAssertTrue(engine.presetChangesPending() > 0);
  engine.doRenderingStateChanged(false);
  XCTAssertEqual(0, engine.presetChangesPending());

  [self waitForExpectations:@[exp]];
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
  harness.renderForDuration(mixer, 0.25);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.renderForDuration(mixer, 0.25);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());

  harness.sendAllOff();
  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 1.0);
  XCTAssertTrue(engine.oneVoicePerKeyModeEnabled());

  harness.sendNoteOn(60);
  harness.renderForDuration(mixer, 0.25);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.00482171215117, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00380147737451, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0023975179065, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0023975179065, samples[3], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineActiveVoiceCount
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto address = DSPHeaders::valueOf(ParameterAddress::activeVoiceCount);
  AUParameter* param = [engine.parameterTree() parameterWithAddress: address];
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  harness.sendNoteOn(60);
  harness.sendNoteOn(72);
  harness.renderForDuration(mixer, 0.2);
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());
  XCTAssertEqual(2.0, param.value);

  harness.sendNoteOff(60);
  harness.renderForDuration(mixer, 0.2);
  XCTAssertEqual(size_t(2), engine.activeVoiceCount());
  XCTAssertEqual(2.0, param.value);

  harness.sendNoteOff(72);
  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
  XCTAssertEqual(0.0, param.value);

  // Should be harmless
  param.value = 99;
  XCTAssertEqual(0.0, param.value);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
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

    auto address = AUParameterAddress(DSPHeaders::valueOf(index));
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
  harness.renderMaxFramesCount(mixer);
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  // Pan left
  auto steps = harness.engine().sampleRate() / harness.maxFramesToRender();
  for (auto step = 1_F; step <= steps; ++step) {
    harness.setParameter(Index::pan, AUValue(step / steps * -500_F));
    harness.renderMaxFramesCount(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    harness.setParameter(Index::pan, AUValue(step / steps * -500_F));
    harness.renderMaxFramesCount(mixer);
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    harness.setParameter(Index::pan, AUValue(step / steps * 500_F));
    harness.renderMaxFramesCount(mixer);
    samples.push_back(harness.lastDrySample(0));
    samples.push_back(harness.lastDrySample(1));
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    harness.setParameter(Index::pan, AUValue(step / steps * 500_F));
    harness.renderMaxFramesCount(mixer);
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];
  auto epsilon = self.epsilon;

  XCTAssertEqualWithAccuracy(-0.0135538503528, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0135538503528, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0229097697884, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0225526988506, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0985833257437, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0952340811491, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00973751116544, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00925995223224, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.028086964041, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.026292514056, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00846939906478, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00777983292937, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0262733697891, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0237564742565, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0454559288919, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0404570810497, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0492616705596, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0430191457272, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00858567003161, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00737962964922, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0155104873702, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0131213050336, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.016893774271, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.014020498842, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0331624299288, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0270851887763, samples[25], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0136835686862, samples[26], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0109979398549, samples[27], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.031662825495, samples[28], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0249609611928, samples[29], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0334168300033, samples[30], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0259207487106, samples[31], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0476124733686, samples[32], self.epsilon);
  XCTAssertEqualWithAccuracy(0.036336697638, samples[33], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0114690810442, samples[34], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00858309026808, samples[35], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0189455542713, samples[36], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0139474626631, samples[37], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00848042126745, samples[38], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00614105677232, samples[39], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0260076485574, samples[40], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0184621848166, samples[41], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0365704074502, samples[42], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0255308561027, samples[43], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0306586995721, samples[44], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0210475157946, samples[45], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0620039626956, samples[46], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0417120829225, samples[47], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0123949386179, samples[48], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00819781050086, samples[49], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0249617472291, samples[50], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.01622893475, samples[51], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00564557407051, samples[52], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0035952408798, samples[53], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0508737973869, samples[54], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0318388827145, samples[55], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0312929451466, samples[56], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0192440226674, samples[57], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0624492131174, samples[58], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0375974811614, samples[59], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0257775727659, samples[60], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0152448145673, samples[61], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0125337727368, samples[62], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00728019373491, samples[63], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0285029113293, samples[64], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.016198489815, samples[65], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0243145227432, samples[66], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0135666560382, samples[67], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0261412989348, samples[68], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.014317875728, samples[69], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0406534224749, samples[70], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0217707753181, samples[71], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0324896089733, samples[72], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0170718953013, samples[73], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0366061776876, samples[74], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0188695918769, samples[75], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00431000534445, samples[76], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00217053527012, samples[77], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0372408851981, samples[78], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0183894205838, samples[79], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0375990867615, samples[80], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0182004030794, samples[81], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0932796448469, samples[82], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0440731719136, samples[83], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0289293900132, samples[84], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0133917722851, samples[85], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00865129381418, samples[86], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00392258074135, samples[87], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0160078201443, samples[88], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00707698520273, samples[89], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0211248565465, samples[90], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00914154388011, samples[91], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00176768982783, samples[92], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000748520251364, samples[93], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0168573129922, samples[94], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00695152534172, samples[95], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0343908965588, samples[96], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0138669032604, samples[97], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0765512734652, samples[98], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0301697831601, samples[99], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00300054810941, samples[100], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0011499999091, samples[101], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0390767976642, samples[102], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0146257653832, samples[103], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0258551500738, samples[104], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00944629311562, samples[105], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0182247199118, samples[106], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00646445341408, samples[107], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0292166173458, samples[108], self.epsilon);
  XCTAssertEqualWithAccuracy(0.010105740279, samples[109], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0501028075814, samples[110], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0168906655163, samples[111], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0389000400901, samples[112], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0127069791779, samples[113], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0134561061859, samples[114], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00427887029946, samples[115], self.epsilon);
  XCTAssertEqualWithAccuracy(0.002793262247, samples[116], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000864124856889, samples[117], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0478765442967, samples[118], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0143181206658, samples[119], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0527750700712, samples[120], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0153325749561, samples[121], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0122936880216, samples[122], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00346717843786, samples[123], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0655059814453, samples[124], self.epsilon);
  XCTAssertEqualWithAccuracy(0.017809856683, samples[125], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00570813938975, samples[126], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00150389317423, samples[127], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0564142391086, samples[128], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0143902963027, samples[129], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.041575036943, samples[130], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0101887304336, samples[131], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0265038777143, samples[132], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0062750200741, samples[133], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0366989485919, samples[134], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00838495977223, samples[135], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.027331719175, samples[136], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00597427133471, samples[137], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.024341352284, samples[138], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00512065365911, samples[139], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00341878086329, samples[140], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000691209919751, samples[141], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0532794743776, samples[142], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0102503672242, samples[143], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022234255448, samples[144], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00409679720178, samples[145], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0372170880437, samples[146], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00655567925423, samples[147], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0605340152979, samples[148], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0100756241009, samples[149], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00647988170385, samples[150], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00102631282061, samples[151], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00160791818053, samples[152], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000241739558987, samples[153], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0584677495062, samples[154], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00822751317173, samples[155], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00840730872005, samples[156], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0011158012785, samples[157], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0474886260927, samples[158], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0059234383516, samples[159], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0281461253762, samples[160], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00324168382213, samples[161], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0752485692501, samples[162], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00806831941009, samples[163], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0163845904171, samples[164], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00162673555315, samples[165], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0226627029479, samples[166], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00203455379233, samples[167], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0944371819496, samples[168], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00773096270859, samples[169], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0155600830913, samples[170], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00115085253492, samples[171], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0168926939368, samples[172], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00108944089152, samples[173], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0335347950459, samples[174], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00189837208018, samples[175], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0262610521168, samples[176], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00127978529781, samples[177], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0414937734604, samples[178], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00163029483519, samples[179], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0464261695743, samples[180], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00145900121424, samples[181], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0173269007355, samples[182], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000408331106883, samples[183], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0529094859958, samples[184], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000748040154576, samples[185], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0105871893466, samples[186], self.epsilon);
  XCTAssertEqualWithAccuracy(-6.65221450618e-05, samples[187], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00957908295095, samples[188], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00973074510694, samples[189], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0163220725954, samples[190], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0168961007148, samples[191], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0438434891403, samples[192], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.046104606241, samples[193], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0187311340123, samples[194], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0200095251203, samples[195], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0103693669662, samples[196], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0112884584814, samples[197], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0055158608593, samples[198], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00610024156049, samples[199], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0195885449648, samples[200], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0220088921487, samples[201], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00840737018734, samples[202], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00962736736983, samples[203], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0454967096448, samples[204], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0529321655631, samples[205], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.015480145812, samples[206], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0182988364249, samples[207], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0526936799288, samples[208], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0634923949838, samples[209], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00135534070432, samples[210], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00165944546461, samples[211], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00237649306655, samples[212], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00295681785792, samples[213], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0118862623349, samples[214], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0150776496157, samples[215], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0228293780237, samples[216], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0294314548373, samples[217], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0121155669913, samples[218], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0158751942217, samples[219], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0528843551874, samples[220], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0706662684679, samples[221], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0128540880978, samples[222], self.epsilon);
  XCTAssertEqualWithAccuracy(0.017460366711, samples[223], self.epsilon);
  XCTAssertEqualWithAccuracy(0.020965192467, samples[224], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0289516374469, samples[225], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0139801120386, samples[226], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0196937583387, samples[227], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00671118218452, samples[228], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00961309950799, samples[229], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000712098553777, samples[230], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00103727169335, samples[231], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0436328798532, samples[232], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0648591816425, samples[233], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0133754592389, samples[234], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.020223448053, samples[235], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000945948529989, samples[236], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00145496474579, samples[237], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0146572478116, samples[238], self.epsilon);
  XCTAssertEqualWithAccuracy(0.023016134277, samples[239], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0256185568869, samples[240], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0409346446395, samples[241], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0245772432536, samples[242], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0399653688073, samples[243], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0238016806543, samples[244], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0395344644785, samples[245], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0341594442725, samples[246], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0577604658902, samples[247], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00448931474239, samples[248], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00772892218083, samples[249], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0132704041898, samples[250], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0233506411314, samples[251], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0481462515891, samples[252], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0862889885902, samples[253], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0127897784114, samples[254], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0233513321728, samples[255], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0150749208406, samples[256], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0281499940902, samples[257], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00405912939459, samples[258], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00772494776174, samples[259], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0112562207505, samples[260], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0218365751207, samples[261], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00844428874552, samples[262], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0167677234858, samples[263], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0223329439759, samples[264], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0452270209789, samples[265], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00401112809777, samples[266], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0082863420248, samples[267], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.010462959297, samples[268], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0221445634961, samples[269], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0239660348743, samples[270], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0517722927034, samples[271], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0173433385789, samples[272], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0382509157062, samples[273], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0202541518956, samples[274], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0458139851689, samples[275], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0152483005077, samples[276], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0352367348969, samples[277], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0107102012262, samples[278], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0252929963171, samples[279], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00452777370811, samples[280], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0109797632322, samples[281], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00534779299051, samples[282], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0132629033178, samples[283], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00519090890884, samples[284], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0131711494178, samples[285], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0246490705758, samples[286], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0643136575818, samples[287], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00778678059578, samples[288], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0208045486361, samples[289], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00894833821803, samples[290], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0244922135025, samples[291], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0185757894069, samples[292], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.052369248122, samples[293], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0101989768445, samples[294], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0294861719012, samples[295], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00227815052494, samples[296], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00675767846406, samples[297], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0190036892891, samples[298], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0581762418151, samples[299], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00159509456716, samples[300], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00501622259617, samples[301], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00465412344784, samples[302], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0150443371385, samples[303], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0113130947575, samples[304], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0378284193575, samples[305], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00683198962361, samples[306], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0235158652067, samples[307], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00736647937447, samples[308], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0261195655912, samples[309], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00658451858908, samples[310], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0242183506489, samples[311], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0102044818923, samples[312], self.epsilon);
  XCTAssertEqualWithAccuracy(0.038731880486, samples[313], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00311916670762, samples[314], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0122280595824, samples[315], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000221645459533, samples[316], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00090442225337, samples[317], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0138896713033, samples[318], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0586659684777, samples[319], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0114489058033, samples[320], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0501090958714, samples[321], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00438171578571, samples[322], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0200459305197, samples[323], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00584736187011, samples[324], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0277958028018, samples[325], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00089557422325, samples[326], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00442958064377, samples[327], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00764597579837, samples[328], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0397423431277, samples[329], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00815420877188, samples[330], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0442547574639, samples[331], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00353126926348, samples[332], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0200472846627, samples[333], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00626234244555, samples[334], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0376239493489, samples[335], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00573504343629, samples[336], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0362096391618, samples[337], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00948112178594, samples[338], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0630631521344, samples[339], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000363218830898, samples[340], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00258116610348, samples[341], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00879739318043, samples[342], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0662863627076, samples[343], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000299945124425, samples[344], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00240467861295, samples[345], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00535382796079, samples[346], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0464849509299, samples[347], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00213019759394, samples[348], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.019867124036, samples[349], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00160503049847, samples[350], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0161659773439, samples[351], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00054416700732, samples[352], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00606142589822, samples[353], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00442709540948, samples[354], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0540789626539, samples[355], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00254078092985, samples[356], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0343525856733, samples[357], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00302868965082, samples[358], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0469623729587, samples[359], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00210211216472, samples[360], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.037133872509, samples[361], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000414227106376, samples[362], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00849989335984, samples[363], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000839659129269, samples[364], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0213707499206, samples[365], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000346722081304, samples[366], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0110328793526, samples[367], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00187804573216, samples[368], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.07969199121, samples[369], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000788095640019, samples[370], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0557426437736, samples[371], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000171928666532, samples[372], self.epsilon);
  XCTAssertEqualWithAccuracy(0.027362935245, samples[373], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
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

  auto exp = [self expectationWithDescription:@"empty queue"];
  harness.postWorkItem(^{ [exp fulfill]; });
  [self waitForExpectations:@[exp]];

  harness.sendRaw(engine.createLoadFileUsePresetPayload("", 128, overrides));

  exp = [self expectationWithDescription:@"empty queue"];
  harness.postWorkItem(^{ [exp fulfill]; });
  [self waitForExpectations:@[exp]];

  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("SynthBass101", engine.activePresetName());

  harness.sendRaw(engine.createLoadFileUsePresetPayload("", engine.presetCount() - 1, overrides));
  std::clog << engine.activePresetName() << '\n';

  exp = [self expectationWithDescription:@"empty queue"];
  harness.postWorkItem(^{ [exp fulfill]; });
  [self waitForExpectations:@[exp]];

  XCTAssertEqual("SFX", engine.activePresetName());
}

- (void)testEngineChangePresetByBankProgram
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);
  XCTAssertEqual("Piano 1", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgramPayload(0, 1));
  harness.drainWorkQueue();
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 2", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgramPayload(1, 38));
  harness.drainWorkQueue();
  std::clog << engine.activePresetName() << '\n';
  XCTAssertEqual("SynthBass101", engine.activePresetName());
  harness.sendRaw(engine.createUseBankProgramPayload(128, 56));
  harness.drainWorkQueue();
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
  // MIDI RP-015: Reset All Controllers keeps bank select, and does not stop notes. (It used to do both.)
  XCTAssertEqual(123u, engine.channelState().continuousControllerValue(MIDI::ControlChange::bankSelectLSB));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
}

- (void)testResetAllControllersReleasesPedalHeldNotes
{
  // CC 121 resets the sustain pedal, so a note held only by the pedal is released exactly as if the pedal were lifted.
  const auto path = self.contexts->context1.path();
  const std::array<uint8_t, 3> resetAll{0xB0, 121, 0};
  auto reference = renderMIDISequence(path, {{5, noteOnBytes(60)}, {25, sustainBytes(true)}, {5, noteOffBytes(60)},
    {25, sustainBytes(false)}});
  auto reset = renderMIDISequence(path, {{5, noteOnBytes(60)}, {25, sustainBytes(true)}, {5, noteOffBytes(60)},
    {25, resetAll}});
  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertTrue(reference == reset);
}

- (void)testResetAllControllersKeepsHeldNotesSounding
{
  // A held note is unaffected by CC 121 when the controllers are already at their reset values.
  const auto path = self.contexts->context1.path();
  const std::array<uint8_t, 3> resetAll{0xB0, 121, 0};
  auto reference = renderMIDISequence(path, {{0.8, noteOnBytes(60)}, {0.2, noteOffBytes(60)}});
  auto reset = renderMIDISequence(path, {{0.6, noteOnBytes(60)}, {0.2, resetAll}, {0.2, noteOffBytes(60)}});
  XCTAssertTrue(reference == reset);
}

- (void)testResetAllControllersRecentresBendButKeepsBendRange
{
  const auto path = self.contexts->context0.path();
  const std::array<uint8_t, 3> resetAll{0xB0, 121, 0};
  const std::array<uint8_t, 3> fullUp{0xE0, 0x7F, 0x7F};
  const std::array<uint8_t, 3> centre{0xE0, 0x00, 0x40};
  const std::array<uint8_t, 3> rpn0Msb{0xB0, 101, 0};
  const std::array<uint8_t, 3> rpn0Lsb{0xB0, 100, 0};
  const std::array<uint8_t, 3> twelveSemitones{0xB0, 6, 12};

  // Pitch bend goes back to centre.
  auto centred = renderMIDISequence(path, {{5, noteOnBytes(60)}, {25, fullUp}, {0, centre}});
  auto reset = renderMIDISequence(path, {{5, noteOnBytes(60)}, {25, fullUp}, {0, resetAll}});
  auto bentThroughout = renderMIDISequence(path, {{5, noteOnBytes(60)}, {0, fullUp}});
  XCTAssertTrue(centred == reset);
  XCTAssertFalse(centred == bentThroughout);

  // The bend range set with RPN 0 survives CC 121 (RP-015 keeps RPN values; it used to go back to 2 semitones).
  auto wide = renderMIDISequence(path, {{0, rpn0Msb}, {0, rpn0Lsb}, {0, twelveSemitones}, {20, noteOnBytes(60)},
    {0, fullUp}});
  auto wideAfterReset = renderMIDISequence(path, {{0, rpn0Msb}, {0, rpn0Lsb}, {0, twelveSemitones},
    {10, noteOnBytes(60)}, {10, resetAll}, {0, fullUp}});
  auto defaultRange = renderMIDISequence(path, {{20, noteOnBytes(60)}, {0, fullUp}});
  XCTAssertTrue(wide == wideAfterReset);
  XCTAssertFalse(wide == defaultRange);
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


- (void)testMIDIPitchBendDecodesFull14BitRange
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};

  // At rest the wheel is centred.
  XCTAssertEqual(8192, engine.channelState().pitchWheelValue());

  // Pitch bend is LSB first, then MSB. 0x2000 (centre) is LSB 0x00, MSB 0x40.
  harness.sendRaw(std::array<uint8_t, 3>{0xE0, 0x00, 0x40});
  XCTAssertEqual(8192, engine.channelState().pitchWheelValue());

  harness.sendRaw(std::array<uint8_t, 3>{0xE0, 0x7F, 0x7F});
  XCTAssertEqual(16383, engine.channelState().pitchWheelValue());

  harness.sendRaw(std::array<uint8_t, 3>{0xE0, 0x00, 0x00});
  XCTAssertEqual(0, engine.channelState().pitchWheelValue());

  harness.sendRaw(std::array<uint8_t, 3>{0xE0, 0x7F, 0x3F});
  XCTAssertEqual(8191, engine.channelState().pitchWheelValue());
}

- (void)testMIDIPitchBendCentreIsNeutral
{
  // A note rendered after an explicit MIDI pitch-bend "centre" message must be identical to one rendered with no
  // pitch-bend message at all. Previously the 14-bit value was clamped to [0, 8191] so centre meant full bend up.
  const auto path = self.contexts->context0.path();
  const std::array<uint8_t, 3> centre{0xE0, 0x00, 0x40};
  const std::array<uint8_t, 3> fullUp{0xE0, 0x7F, 0x7F};
  const std::array<uint8_t, 3> fullDown{0xE0, 0x00, 0x00};

  auto reference = renderNoteAfterPitchBend(path, nullptr);
  auto centred = renderNoteAfterPitchBend(path, &centre);
  auto up = renderNoteAfterPitchBend(path, &fullUp);
  auto down = renderNoteAfterPitchBend(path, &fullDown);

  // Guard against a vacuous comparison of two silent buffers.
  auto peak = std::accumulate(reference.begin(), reference.end(), AUValue(0),
                              [](AUValue acc, AUValue v) { return std::max(acc, std::abs(v)); });
  XCTAssertGreaterThan(peak, 0.01f);

  XCTAssertEqual(reference.size(), centred.size());
  XCTAssertTrue(reference == centred);

  // Bending away from centre must change the rendering, and in different ways for up and down.
  XCTAssertFalse(reference == up);
  XCTAssertFalse(reference == down);
  XCTAssertFalse(up == down);
}


- (void)testRPN0PitchWheelSensitivityControlsBendRange
{
  // SF2.01 8.2.1 source 16 / 8.4.10: the default pitch wheel modulator scales its amount by the pitch wheel
  // sensitivity, which MIDI sets with RPN 0. Previously RPN 0 was not decoded, so the range was always 2 semitones.
  using Bytes = std::array<uint8_t, 3>;
  const Bytes selectRPN0Msb{0xB0, 101, 0};
  const Bytes selectRPN0Lsb{0xB0, 100, 0};
  const Bytes fullUp{0xE0, 0x7F, 0x7F};
  auto dataEntry = [](uint8_t semitones) { return Bytes{0xB0, 6, semitones}; };

  // Render a note, sending `before` ahead of the note-on and `after` once it sounds.
  const auto path = self.contexts->context0.path();
  auto render = [&path](std::vector<Bytes> before, std::vector<Bytes> after) {
    auto harness{TestEngineHarness{48000.0}};
    harness.load(path, 0);
    auto mixer{harness.createMixer(0.25)};
    for (const auto& bytes : before) harness.sendRaw(bytes);
    harness.sendNoteOn(60, 100);
    for (const auto& bytes : after) harness.sendRaw(bytes);
    harness.renderToEnd(mixer);
    const AUValue* data = harness.dryBuffer().floatChannelData[0];
    return std::vector<AUValue>(data, data + harness.bufferFrameCount());
  };

  auto unbent = render({}, {});
  auto defaultBend = render({fullUp}, {});
  XCTAssertFalse(unbent == defaultBend);

  // A range of 0 semitones: the bend has no effect, whether RPN 0 arrives before the note or while it sounds.
  XCTAssertTrue(render({selectRPN0Msb, selectRPN0Lsb, dataEntry(0), fullUp}, {}) == unbent);
  XCTAssertTrue(render({fullUp}, {selectRPN0Msb, selectRPN0Lsb, dataEntry(0)}) == unbent);

  // A range of 2 semitones is the default.
  XCTAssertTrue(render({selectRPN0Msb, selectRPN0Lsb, dataEntry(2), fullUp}, {}) == defaultBend);

  // A wider range bends further than the default.
  auto wide = render({selectRPN0Msb, selectRPN0Lsb, dataEntry(12), fullUp}, {});
  XCTAssertFalse(wide == defaultBend);
  XCTAssertFalse(wide == unbent);
}

- (void)testShortLoopAtHighPitchKeepsLooping
{
  // §3.3: a loop shorter than the per-sample increment used to be wrapped by a single subtraction, so the play position
  // drifted past the loop and on past the end of the samples. Use a 4-sample loop and play 3 octaves above the root
  // key (an increment of about 7.35 samples). The note must keep looping, with bounded output, for the whole render.
  auto builder = SF2Builder::minimal();
  builder.shdr[0].startLoop = 100;
  builder.shdr[0].endLoop = 104;
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibShortLoop.sf2";
  builder.writeTo(path);

  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(path, 0), IO::File::LoadResponse::ok);
  auto mixer{harness.createMixer(0.5)};
  harness.sendNoteOn(69 + 36, 127);
  harness.renderToEnd(mixer);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(1));

  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  std::vector<AUValue> samples(data, data + harness.bufferFrameCount());
  XCTAssertTrue(std::all_of(samples.begin(), samples.end(), [](AUValue v) { return std::isfinite(v) && std::abs(v) < 1; }));
  // Still sounding in the last 100 ms (the sample itself is only 2000 frames long).
  XCTAssertGreaterThan(rms(samples, samples.size() - 4'800, samples.size()), 0.001);
}

- (void)testVolumeEnvelopeAttackIsLinearInAmplitude
{
  // SF2.01 8.1.2 #34: the volume envelope attack is "convex" so that the result is linear in amplitude. Play the
  // minimal looped sine with a 1 second attack and compare the level at 25%, 50% and 75% of the attack with the level
  // once the attack has finished. Previously the attack was linear in dB, so half way through it was at -48 dB.
  auto builder = SF2Builder::minimal();
  builder.igen.insert(builder.igen.begin(), {SF2Builder::Gen{34, 0}}); // attackVolEnv = 0 timecents = 1 second
  builder.ibag[1].generatorIndex += 1;
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibAttack.sf2";
  builder.writeTo(path);

  auto harness{TestEngineHarness{48000.0}};
  XCTAssertEqual(harness.load(path, 0), IO::File::LoadResponse::ok);
  auto mixer{harness.createMixer(1.5)};
  harness.sendNoteOn(69, 127);
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  std::vector<AUValue> samples(data, data + harness.bufferFrameCount());

  // RMS over 10 ms windows (just under 4.5 cycles of the 441 Hz sine), centred on each point. The default delay is
  // -12000 timecents (about 1 ms), which shifts the attack by less than 0.1%.
  auto windowRMS = [&samples](double seconds) {
    auto centre = size_t(seconds * 48'000);
    return rms(samples, centre - 240, centre + 240);
  };
  auto full = windowRMS(1.25);
  XCTAssertGreaterThan(full, 0.01);
  for (double fraction : {0.25, 0.5, 0.75}) {
    // Allow for the 1 cB resolution of `DSP::centibelsToAttenuation` (about 1.2% in amplitude) and the window.
    XCTAssertEqualWithAccuracy(windowRMS(fraction) / full, fraction, fraction * 0.03, @"at %.0f%%", fraction * 100);
  }
}

- (void)testVolumeEnvelopeSustainLevelIsAppliedInDecibels
{
  // Spec 8.1.2 sustainVolEnv: a value of 120 means the sustain level is 12 dB below peak. Render the same note with
  // sustain 0 cB and 120 cB; once both are in the sustain stage the ratio of their levels must be 10^(-12/20) ~= 0.2512.
  // Previously the sustain level was converted to an amplitude ratio and then converted *again* to centibels by the
  // voice, giving ~72 dB of attenuation instead of 12 dB.
  const auto path = self.contexts->context0.path();
  auto full = renderNoteWithVolumeSustain(path, 0);
  auto reduced = renderNoteWithVolumeSustain(path, 120);
  XCTAssertEqual(full.size(), reduced.size());

  // Skip the first 100 ms so that both renderings are well into the sustain stage.
  auto begin = size_t(0.1 * 48'000);
  auto end = full.size();
  auto fullRMS = rms(full, begin, end);
  auto reducedRMS = rms(reduced, begin, end);
  XCTAssertGreaterThan(fullRMS, 0.001);

  auto expected = std::pow(10.0, -120.0 / 200.0);
  // Allow ~2% for integer-centibel rounding when modLFO-to-volume is also active in the preset.
  XCTAssertEqualWithAccuracy(reducedRMS / fullRMS, expected, expected * 0.02);
}

- (void)testSustainPedalTapDoesNotReleaseHeldKey
{
  // Hold a key, tap the sustain pedal down and up, then release the key. The tap must have no audible effect: the
  // rendering must match one with no pedal at all. Previously, lifting the pedal released every voice, including
  // ones whose key was still down.
  const auto path = self.contexts->context1.path();
  auto reference = renderMIDISequence(path, {
    {20, noteOnBytes(60)},
    {20, noteOffBytes(60)}
  });
  auto tapped = renderMIDISequence(path, {
    {10, noteOnBytes(60)},
    {0, sustainBytes(true)},
    {10, sustainBytes(false)},
    {20, noteOffBytes(60)}
  });
  auto releasedAtTap = renderMIDISequence(path, {
    {10, noteOnBytes(60)},
    {30, noteOffBytes(60)}
  });

  XCTAssertEqual(reference, tapped);
  XCTAssertNotEqual(reference, releasedAtTap);
}

- (void)testSustainPedalReleasesPostponedNoteWhenLifted
{
  // A note released while the sustain pedal is down keeps sounding until the pedal lifts. It then sounds exactly like a
  // note released at the time the pedal lifted.
  const auto path = self.contexts->context1.path();
  auto reference = renderMIDISequence(path, {
    {20, noteOnBytes(60)},
    {20, noteOffBytes(60)}
  });
  auto sustained = renderMIDISequence(path, {
    {10, noteOnBytes(60)},
    {0, sustainBytes(true)},
    {10, noteOffBytes(60)},
    {20, sustainBytes(false)}
  });
  XCTAssertEqual(reference, sustained);
}

- (void)testSustainPedalLiftOnlyReleasesNotesWhoseKeysAreUp
{
  // Two notes under the sustain pedal: 60 is released while the pedal is down, 64 stays held. Lifting the pedal releases
  // 60 only. 64 sounds until its own note-off.
  const auto path = self.contexts->context1.path();
  auto reference = renderMIDISequence(path, {
    {10, noteOnBytes(60)},
    {10, noteOnBytes(64)},
    {20, noteOffBytes(60)},
    {20, noteOffBytes(64)}
  });
  auto sustained = renderMIDISequence(path, {
    {10, noteOnBytes(60)},
    {10, noteOnBytes(64)},
    {0, sustainBytes(true)},
    {0, noteOffBytes(60)},
    {20, sustainBytes(false)},
    {0, noteOffBytes(64)}
  });
  XCTAssertEqual(reference, sustained);
}

- (void)testSostenutoPedalHoldsOnlyCapturedNotes
{
  // 60 is down when sostenuto goes down, so it is captured. 64 starts afterwards and must release normally. 60 is
  // released while the pedal is down, so it sounds until the pedal lifts.
  const auto path = self.contexts->context1.path();
  // Each entry is (event, then render this long): events at blocks 0, 10, 20, 40 and 0, 5, 10, 20, 25, 40.
  auto reference = renderMIDISequence(path, {
    {10, noteOnBytes(60)},
    {10, noteOnBytes(64)},
    {20, noteOffBytes(64)},
    {0, noteOffBytes(60)}
  });
  auto held = renderMIDISequence(path, {
    {5, noteOnBytes(60)},
    {5, sostenutoBytes(true)},
    {10, noteOnBytes(64)},
    {5, noteOffBytes(64)},
    {15, noteOffBytes(60)},
    {0, sostenutoBytes(false)}
  });
  XCTAssertEqual(reference, held);
}

- (void)testLowPassFilterCutoffAttenuatesOutput
{
  // initialFilterFc (gen 8) at its minimum of 1500 cents (~20 Hz) removes nearly all of a middle-C note. Before the
  // filter was enabled this generator had no effect at all.
  const auto path = self.contexts->context0.path();
  auto open = renderNoteWithGenerators(path, {{Index::initialFilterCutoff, 13'500}});
  auto closed = renderNoteWithGenerators(path, {{Index::initialFilterCutoff, 1'500}});
  auto openRMS = rms(open, 0, open.size());
  XCTAssertGreaterThan(openRMS, 0.001);
  XCTAssertLessThan(rms(closed, 0, closed.size()), 0.1 * openRMS);
}

- (void)testLowPassFilterResonanceLowersDCGain
{
  // initialFilterQ (gen 9) of 200 cB lowers the gain at DC by 10 dB (SF2.01 8.1.2 #9). With the cutoff wide open,
  // almost all of the note's energy is in that flat pass band, so the note gets ~10 dB quieter.
  const auto path = self.contexts->context0.path();
  auto flat = renderNoteWithGenerators(path, {{Index::initialFilterCutoff, 13'500},
    {Index::initialFilterResonance, 0}});
  auto resonant = renderNoteWithGenerators(path, {{Index::initialFilterCutoff, 13'500},
    {Index::initialFilterResonance, 200}});
  auto ratio = rms(resonant, 0, resonant.size()) / rms(flat, 0, flat.size());
  auto expected = std::pow(10.0, -10.0 / 20.0);
  XCTAssertEqualWithAccuracy(ratio, expected, expected * 0.1);
}

- (void)testModEnvelopeToFilterCutoffOpensFilter
{
  // modEnvToFilterFc (gen 11): with the mod envelope at full scale, +12000 cents takes a 1500 cent cutoff up to 13500.
  // That should sound like the filter set to 13500 directly.
  const auto path = self.contexts->context0.path();
  auto reference{instantModEnvelope};
  reference.emplace_back(Index::initialFilterCutoff, 13'500);
  auto swept{instantModEnvelope};
  swept.emplace_back(Index::initialFilterCutoff, 1'500);
  swept.emplace_back(Index::modulatorEnvelopeToFilterCutoff, 12'000);
  auto closed{instantModEnvelope};
  closed.emplace_back(Index::initialFilterCutoff, 1'500);

  auto referenceRMS = rms(renderNoteWithGenerators(path, reference), 0, size_t(0.25 * 48'000));
  auto sweptRMS = rms(renderNoteWithGenerators(path, swept), 0, size_t(0.25 * 48'000));
  auto closedRMS = rms(renderNoteWithGenerators(path, closed), 0, size_t(0.25 * 48'000));
  XCTAssertGreaterThan(referenceRMS, 0.001);
  XCTAssertEqualWithAccuracy(sweptRMS / referenceRMS, 1.0, 0.05);
  XCTAssertLessThan(closedRMS, 0.1 * referenceRMS);
}

- (void)testModLFOToFilterCutoffModulatesFilter
{
  // modLfoToFilterFc (gen 10): an LFO swinging the cutoff by +/-12000 cents around 1500 cents opens the filter for
  // half of each cycle, so the note is much louder than with the filter closed, but no louder than fully open.
  const auto path = self.contexts->context0.path();
  auto open = renderNoteWithGenerators(path, {{Index::initialFilterCutoff, 13'500}});
  auto closed = renderNoteWithGenerators(path, {{Index::initialFilterCutoff, 1'500}});
  auto swept = renderNoteWithGenerators(path, {{Index::initialFilterCutoff, 1'500},
    {Index::modulatorLFOToFilterCutoff, 12'000}, {Index::delayModulatorLFO, -12'000},
    {Index::frequencyModulatorLFO, 0}});
  auto openRMS = rms(open, 0, open.size());
  auto sweptRMS = rms(swept, 0, swept.size());
  XCTAssertGreaterThan(sweptRMS, 3.0 * rms(closed, 0, closed.size()));
  XCTAssertLessThan(sweptRMS, 1.05 * openRMS);
}

- (void)testStartAddressOffsetChangesRenderedNote
{
  // startAddrsOffset (gen 0) set as an AU parameter must change where playback begins. Previously the index always
  // started at 0, and the bounds were computed before live parameters were applied, so this had no effect.
  const auto path = self.contexts->context0.path();
  auto reference = renderNoteWithGenerators(path, {});
  auto offset = renderNoteWithGenerators(path, {{Index::startAddressOffset, 2'000}});
  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertFalse(reference == offset);

  // Setting it back to zero restores the original rendering exactly.
  auto restored = renderNoteWithGenerators(path, {{Index::startAddressOffset, 0}});
  XCTAssertEqual(reference, restored);
}

- (void)testStartAddressCoarseOffsetPastEndOfSampleIsSilent
{
  // startAddrsCoarseOffset (gen 4) of 1000 x 32768 samples is far beyond any sample in the file. The start clamps to
  // the end of the sample, so the note produces no audio and its voice finishes straight away.
  const auto path = self.contexts->context0.path();
  auto harness{TestEngineHarness{48000.0}};
  harness.load(path, 0);
  harness.setParameter(Index::startAddressCoarseOffset, 1'000);
  auto mixer{harness.createMixer(0.25)};
  harness.sendNoteOn(60, 127);
  XCTAssertGreaterThan(harness.engine().activeVoiceCount(), size_t(0));
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  std::vector<AUValue> samples(data, data + harness.bufferFrameCount());
  XCTAssertEqual(rms(samples, 0, samples.size()), 0.0);
  XCTAssertEqual(harness.engine().activeVoiceCount(), size_t(0));
}

- (void)testProgramChangeAfterBookmarkLoadReadsSamples
{
  // On the bookmark path the NSFileHandle (and its descriptor) is released as soon as the file has been parsed. A
  // later MIDI program change loads that preset's samples from the file, which used to fail on the closed descriptor
  // (or, worse, read whichever file had reused its number). The note after the program change must sound exactly as it
  // does when the same file is loaded by path.
  auto render = [](TestEngineHarness& harness) {
    auto mixer{harness.createMixer(0.25)};
    harness.sendRaw(std::array<uint8_t, 3>{0xC0, 23, 0}); // program change to 23 (padded to 3 bytes)
    harness.drainWorkQueue(); // the program change loads on the work queue
    harness.sendNoteOn(64, 127);
    harness.renderToEnd(mixer);
    const AUValue* data = harness.dryBuffer().floatChannelData[0];
    return std::vector<AUValue>(data, data + harness.bufferFrameCount());
  };

  auto byPath{TestEngineHarness{48000.0}};
  XCTAssertEqual(byPath.load(self.contexts->context0.path(), 0), IO::File::LoadResponse::ok);
  auto reference = render(byPath);
  auto referenceName = byPath.engine().activePresetName();

  const NSURL* url = self.contexts->context0.url();
  NSError* error = nil;
  NSData* bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationMinimalBookmark
                   includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
  XCTAssertNil(error);

  auto byBookmark{TestEngineHarness{48000.0}};
  // The NSFileHandle is autoreleased. Drain a pool here so that it is really gone (and its descriptor closed) before
  // the program change, as it is in a host once the work-queue block returns.
  @autoreleasepool {
    XCTAssertEqual(byBookmark.engine().loadBookmarkAndPreset(bookmark, 0), IO::File::LoadResponse::ok);
  }
  // Open another file so that, without the fix, the released descriptor number gets reused.
  int other = ::open("/dev/zero", O_RDONLY);
  auto viaBookmark = render(byBookmark);
  ::close(other);

  XCTAssertNotEqual(referenceName, std::string("Piano 1"));
  XCTAssertEqual(byBookmark.engine().activePresetName(), referenceName);
  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertTrue(reference == viaBookmark);
}

- (void)testSostenutoPedalTapDoesNotReleaseHeldKey
{
  const auto path = self.contexts->context1.path();
  auto reference = renderMIDISequence(path, {
    {100, noteOnBytes(60)},
    {0, noteOffBytes(60)}
  });
  auto tapped = renderMIDISequence(path, {
    {80, noteOnBytes(60)},
    {0, sostenutoBytes(true)},
    {20, sostenutoBytes(false)},
    {0, noteOffBytes(60)}
  });
  XCTAssertEqual(reference, tapped);
}

- (void)testStoppedVoiceDoesNotWriteRestOfSlice
{
  // §6 item 4: after a voice stopped part-way through a render slice, `Voice::renderInto` added 0 to every remaining
  // frame. That is pure overhead. It is inaudible, but adding +0.0 turns -0.0 into +0.0, so pre-fill the output with -0.0
  // and check that the frames after the voice stopped are left alone.
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibStoppedVoice.sf2";
  SF2Builder::minimal().writeTo(path);
  auto harness{TestEngineHarness{48000.0}};
  XCTAssertEqual(harness.load(path, 0), SF2::IO::File::LoadResponse::ok);
  auto mixer{harness.createMixer(512.0 / 48000.0)};
  for (int channel = 0; channel < 2; ++channel) {
    float* data = harness.dryBuffer().floatChannelData[channel];
    std::fill(data, data + harness.bufferFrameCount(), -0.0f);
  }

  // The default release is about 1 ms, so the voice stops early in the second slice of 448 frames.
  harness.sendNoteOn(69, 127);
  harness.renderForCount(mixer, 64);
  harness.sendNoteOff(69);
  harness.renderForCount(mixer, 448);
  XCTAssertEqual(harness.engine().activeVoiceCount(), size_t(0));

  const float* left = harness.dryBuffer().floatChannelData[0];
  double level = 0.0;
  for (size_t index = 0; index < 64; ++index) level = std::max(level, std::abs(double(left[index])));
  XCTAssertGreaterThan(level, 0.01);  // the note did sound

  size_t overwritten = 0;
  for (int channel = 0; channel < 2; ++channel) {
    const float* data = harness.dryBuffer().floatChannelData[channel];
    for (size_t index = 256; index < 512; ++index) if (!std::signbit(data[index])) ++overwritten;
  }
  XCTAssertEqual(overwritten, size_t(0));
}

- (void)testActiveVoiceCountIsPublishedToParameterObservers
{
  // The active voice count used to be set on the `activeVoiceCount` parameter from the render thread. That was removed
  // (Objective-C messaging is not real-time safe) with no replacement, so a UI observing the parameter stopped seeing
  // it. Now the render thread shares the count through an atomic and a timer publishes it while rendering.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertTrue(engine.isRendering());
  harness.load(self.contexts->context0.path(), 0);
  auto mixer{harness.createMixer(1.0)};

  auto address = DSPHeaders::valueOf(SF2::Render::Engine::ParameterAddress::activeVoiceCount);
  auto sawThree = [self expectationWithDescription:@"observer saw 3 active voices"];
  auto sawZero = [self expectationWithDescription:@"observer saw 0 active voices again"];
  __block bool seenThree = false;
  __block bool seenZero = false;
  auto token = [engine.parameterTree() tokenByAddingParameterObserver:^(AUParameterAddress changed, AUValue value) {
    if (changed != address) return;
    if (!seenThree && value == 3) { seenThree = true; [sawThree fulfill]; }
    else if (seenThree && !seenZero && value == 0) { seenZero = true; [sawZero fulfill]; }
  }];

  for (uint8_t key : {60, 64, 67}) harness.sendNoteOn(key, 100);
  harness.renderForDuration(mixer, 0.1);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(3));
  [self waitForExpectations:@[sawThree] timeout:2.0];
  XCTAssertEqual([engine.parameterTree() parameterWithAddress:address].value, 3.0);

  for (uint8_t key : {60, 64, 67}) harness.sendNoteOff(key);
  harness.renderToEnd(mixer);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(0));
  [self waitForExpectations:@[sawZero] timeout:2.0];
  XCTAssertEqual([engine.parameterTree() parameterWithAddress:address].value, 0.0);

  [engine.parameterTree() removeParameterObserver:token];
}

@end
