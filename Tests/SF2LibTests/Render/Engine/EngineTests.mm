// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <array>
#include <cmath>
#include <iostream>
#include <numeric>
#include <vector>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"

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
  return std::vector<AUValue>(data, data + harness.duration());
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
  return std::vector<AUValue>(data, data + harness.duration());
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
  return std::vector<AUValue>(data, data + harness.duration());
}

/// Mod envelope that jumps straight to full scale and stays there.
static const std::vector<std::pair<Index, AUValue>> instantModEnvelope{
  {Index::delayModulatorEnvelope, -12'000}, {Index::attackModulatorEnvelope, -12'000},
  {Index::holdModulatorEnvelope, -12'000}, {Index::decayModulatorEnvelope, -12'000},
  {Index::sustainModulatorEnvelope, 0}};

/// A 3-byte MIDI message to send just before the render block with the given index.
using TimedMIDIEvents = std::vector<std::pair<AVAudioFrameCount, std::array<uint8_t, 3>>>;

/// Render 1 second of preset 0 of the given file, sending each MIDI message at its render-block index. Events must be in
/// render-block order. Returns the left channel of the dry bus.
static std::vector<AUValue> renderMIDISequence(const std::string& path, const TimedMIDIEvents& events)
{
  auto harness{TestEngineHarness{48000.0}};
  harness.load(path, 0);
  auto mixer{harness.createMixer(1.0)};
  for (const auto& [renderIndex, bytes] : events) {
    harness.renderUntil(mixer, renderIndex);
    harness.sendRaw(bytes);
  }
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + harness.duration());
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
}

- (void)testInit {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Interpolator::linear, -1.0);
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

  XCTAssertEqual(size_t(42), engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self dumpSamples: samples];

  auto epsilon = self.epsilon;
  XCTAssertEqualWithAccuracy(0.0654075965285, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0353105515242, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0660973936319, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126845063642, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0483601689339, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.0664567351341, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.0342636294663, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0660993605852, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126720331609, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0483443923295, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0664635524154, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0342636294663, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.0660993605852, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126720331609, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0483443923295, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.0664635524154, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0342636294663, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0660993605852, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126720331609, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0483443923295, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0664635524154, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0342636294663, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.0660993605852, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126720331609, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.0483443923295, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[25], epsilon);

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

  XCTAssertEqual(size_t(42), engine.activeVoiceCount());
  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self dumpSamples: samples];

  auto epsilon = self.epsilon;
  XCTAssertEqualWithAccuracy(0.0653873682022, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0353040844202, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0660770013928, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127479061484, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0483480766416, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.0664769932628, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.0342639796436, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.066099897027, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127423256636, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0483323186636, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0664464905858, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0342572517693, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.0660787820816, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127260638401, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0483488105237, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.0664619281888, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0342523530126, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0660787671804, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127351982519, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.048332285136, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0664462074637, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0342858918011, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.0660996288061, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126714939252, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.0483240373433, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[25], epsilon);

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

  XCTAssertEqualWithAccuracy(0.00320581975393, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0275035277009, samples[1], self.epsilon);

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

- (void)testEngineMIDINoteRandomNoteOff
{
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  int seconds = 2;
  auto mixer{harness.createMixer(seconds)};
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  harness.sendNoteOn(40);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.2));

  harness.sendNoteOff(40);
  harness.sendNoteOff(40);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.4));

  harness.sendNoteOn(41);
  harness.sendNoteOn(42);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.6));

  harness.sendNoteOff(41);
  harness.sendNoteOff(41);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.8));

  harness.sendNoteOff(42);
  harness.sendNoteOff(42);
  harness.sendNoteOff(42);

  harness.renderToEnd(mixer);

  XCTAssertEqual(size_t(0), engine.activeVoiceCount());

  [self playSamples: harness.dryBuffer() count: harness.duration()];
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
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.5));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());

  harness.sendNoteOn(40, 0);
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

  XCTAssertEqualWithAccuracy(-0.118742279708, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.055044580251, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.043859295547, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0183677896857, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00949102640152, samples[4], self.epsilon);

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

  XCTAssertEqualWithAccuracy(-0.0145196141675, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0093383230269, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00529375206679, samples[2], self.epsilon);

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

  XCTAssertEqualWithAccuracy(-0.0529685467482, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.023867290467, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00398819381371, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000226258824114, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.023965395987, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-4.42016789748e-05, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(8.02297581686e-05, samples[6], self.epsilon);

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

  XCTAssertEqualWithAccuracy(-0.0529685467482, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.023867290467, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00384210678749, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00444519985467, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000223419629037, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0045163789764, samples[5], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
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

  auto epsilon = self.epsilon;
  XCTAssertEqualWithAccuracy(0.0433960258961, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0433960258961, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0047103241086, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00459340587258, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.0011793365702, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112149771303, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.043216381222, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0402013249695, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.00627208594233, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.00568917486817, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0358424894512, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0316996052861, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.0214586853981, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0185030400753, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0573218688369, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0494265556335, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0126105286181, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0106002567336, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0175885520875, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0144114475697, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0739421844482, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0592388622463, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0122930761427, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00959749519825, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.0134716723114, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.0102478098124, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.0270047727972, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.0200116708875, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.0211245194077, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.0156541578472, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.033679202199, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.0243080817163, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.0379457771778, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.0267578847706, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.0142872333527, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.0098083326593, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.0439903214574, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0293933916837, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.00887855142355, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.00577240996063, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.0143087124452, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.00904908776283, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.0364879742265, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.0230756551027, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.00715172942728, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.00441355071962, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.0434164069593, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.026045974344, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.0630756318569, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.0367698669434, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.00796302687377, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.00450893398374, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.00358245475218, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.00196947110817, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0219359174371, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.011702850461, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.0164456814528, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.00877380184829, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.0446737110615, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.0232061333954, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.00312772742473, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.00157513527665, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00999144278467, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.00487531116232, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.00738088879734, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.00348735228181, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.04728006199, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.021616563201, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.0252259168774, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.0111996624619, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.0191591493785, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.00850617326796, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.0712273418903, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.0305575113744, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.0223033633083, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00923835486174, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.0133916866034, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.00535087054595, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.0205162037164, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.00790009368211, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.00499398540705, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.00186022324488, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.00301484856755, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112300924957, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.0184687152505, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.00661639450118, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.0907667279243, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0312357712537, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.0151854716241, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.00501329591498, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.00832504592836, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.00263286661357, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.0100256456062, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.00303264963441, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.0251461230218, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.00730562442914, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.00240415520966, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(0.000698471441865, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.062116637826, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.0172031186521, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.0227955076844, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.0060058105737, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.025682605803, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.00642244098708, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.00712646357715, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.00168725149706, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.0414357446134, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00933034997433, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.0180360451341, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.0038238093257, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.0479862093925, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.0101735256612, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.00358398444951, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(0.00071289925836, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.088593788445, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.0164678748697, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.0237897969782, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.00411348696798, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.0306257419288, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.00494931777939, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.00869000703096, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.0012925285846, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.014343297109, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.00194948771968, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.00147662498057, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-0.000200697453693, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0598224699497, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00736647378653, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.00084288418293, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(9.30554233491e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(-0.000960512086749, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(-9.38403536566e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.0620033033192, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.00537006836385, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.00373956933618, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(0.000276585342363, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.00116243306547, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(7.13010667823e-05, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.0762651264668, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00467793550342, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.0313356183469, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.00152708531823, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.0594431497157, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.00214851577766, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.00824519433081, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-0.000207267992664, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.014866839163, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-0.000186832068721, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.00894772075117, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.0476220995188, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.0356721282005, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.0356721282005, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.00642466451973, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.00658819684759, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.0168503578752, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.017719373107, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.0388610959053, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.0417756326497, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.028216028586, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.0311070308089, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.0332039557397, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.0375434495509, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254067108035, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.0287271663547, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.01793362014, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.0207983031869, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.00763808842748, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.00908660329878, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.00906410720199, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.0110623519868, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.0088398847729, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.0110339801759, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.0423849225044, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.054289277643, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.0136621333659, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.017499320209, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.0157630033791, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.0207218937576, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.0330734997988, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.0446310713887, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.0182655155659, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.0253071375191, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.00413686409593, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.00586655363441, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.03462895751, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.0504420101643, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.00298444181681, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00434726383537, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.00874610804021, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.0130894761533, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.0215035043657, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.0330745689571, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.0130827128887, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0206868108362, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0142574766651, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.0231028571725, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.0129181435332, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.0215334370732, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.0202017538249, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.0346544161439, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.00634151650593, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.0108783394098, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(0.000466704368591, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(0.000824224203825, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.0290445648134, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.0528318658471, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.0241759773344, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.0453156456351, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.00944214127958, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.018176894635, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127827636898, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.025382578373, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.00204162392765, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.00405402854085, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.0177405402064, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.0363573953509, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.0192387644202, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.0407183170319, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.00847291853279, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.018532089889, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.0154805611819, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.034868132323, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.0144655779004, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.0337182097137, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.0251430980861, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.0586067289114, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.000997572205961, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.0024083526805, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.0247994214296, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.0620658062398, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.000863040331751, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.00224127899855, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.0163455158472, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.043881431222, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.00673998333514, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.0188136957586, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.00548568833619, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.0153125096112, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.00198869151063, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.00577885517851, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.0170271042734, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.0515757761896, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.0103776231408, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.0328137353063, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.0136299775913, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.0450593829155, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.0103774126619, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.0357192903757, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.00226749153808, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.00818740576506, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.00571303255856, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.0206284876913, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.00282139051706, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.0107088051736, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.0193308591843, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.0773018971086, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.0128471786156, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.0542627722025, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.00601584697142, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.026716157794, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.00110327871516, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.00520391203463, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.00805893726647, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.0380121767521, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(6.90575689077e-07, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(3.47197055817e-06, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.00482104672119, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.0259362440556, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00983055029064, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.0568536520004, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.0103341359645, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.0639463067055, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.00506334286183, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.0340421758592, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.00567930797115, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.0381834656, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(0.000288506853394, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.00212268158793, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(0.000380842247978, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.0030927862972, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.00197152327746, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.0178578309715, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.0061973691918, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.0634336546063, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(0.000645461026579, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.00745255127549, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.00156044121832, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.0180170014501, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.00128849642351, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.0174210947007, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.00442982465029, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.0722201392055, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.00131536147092, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.0269910711795, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.00172833213583, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.0478178933263, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(0.000208125027712, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.00827928818762, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0.000905319000594, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.0720392093062, samples[301], epsilon);

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

  XCTAssertEqualWithAccuracy(-0.00523802358657, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00267931469716, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00621262798086, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000403643760365, samples[3], self.epsilon);

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
  XCTAssertEqual(2.0, param.value);

  harness.sendNoteOff(60);
  harness.renderUntil(mixer, AVAudioFrameCount(harness.renders() * 0.5));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  XCTAssertEqual(1.0, param.value);

  harness.sendNoteOff(72);
  harness.renderToEnd(mixer);
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
  XCTAssertEqual(0.0, param.value);

  // Should be harmless
  param.value = 99;
  XCTAssertEqual(0.0, param.value);
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
  auto epsilon = self.epsilon;

  XCTAssertEqualWithAccuracy(0.0433960258961, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0433960258961, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.004703104496, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00460079684854, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.00117403827608, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112704280764, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.0430264547467, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0404045321047, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.00623621605337, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.00572847109288, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0355421416461, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0320359990001, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.021253939718, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0187378674746, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0573218688369, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0494265556335, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0125771649182, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0106398211792, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.017520442605, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0144941704348, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0736622065306, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0595866441727, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0122173205018, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0096937501803, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.0133744925261, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.010374320671, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.0267831068486, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.0203073900193, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.0210999064147, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.0156873203814, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.0336026735604, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.0244137682021, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.0378615260124, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.0268769618124, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.0142253227532, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.00989790726453, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.0437581129372, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0297379810363, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.00882375333458, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.00585583085194, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.0141938710585, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.00922817736864, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.0364516824484, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.0231329426169, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.00714478828013, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.00442477921024, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.0432931855321, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.0262502785772, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.0628433525562, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.0371654555202, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.00792736932635, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.00457133632153, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.00356058217585, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.00200874311849, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0217871256173, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.0119775738567, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.0164318829775, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.008799623698, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.0446005836129, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.0233463663608, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.00312027009204, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.00158985680901, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00996061321348, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.00493799243122, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.00734769087285, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.00355676095933, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.0470395237207, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.0221351198852, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.0251012463123, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.0114763537422, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.0191457644105, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.00853625778109, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.0711309909821, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.0307811293751, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.0222595799714, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00934335403144, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.013349249959, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.0054558836855, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.0204408373684, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.00809310004115, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.00497623160481, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.00190720753744, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.00301484856755, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112300924957, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.0184582993388, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.00664539681748, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.0906681492925, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0315207690001, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.0151536725461, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.00510860886425, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.00830411165953, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.00269816955552, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.00999661907554, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.00312700262293, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.0250642765313, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.00758167402819, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.00240415520966, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(0.000698471441865, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.062089536339, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.0173006691039, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.0227669514716, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.00611316459253, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.025641746819, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.00658368179575, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.00711299199611, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.00174316926859, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.0413459688425, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00972045212984, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.0179929025471, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.00402189139277, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.0479862093925, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.0101735256612, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.00358172878623, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(0.000724154990166, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.0885152071714, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.0168851781636, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.0237634778023, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.00426288042217, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.0305859260261, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.00518969632685, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.00867744069546, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.00137437158264, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.0143209975213, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.00210707914084, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.00147630646825, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-0.000203016679734, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0597990304232, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00755437510088, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.000842435285449, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(9.7026117146e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(-0.000959743745625, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(-0.000101381214336, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.0619592145085, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.00585687020794, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.0037367939949, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(0.000311816809699, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.0011614440009, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(8.59026331455e-05, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.0762576907873, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00479772686958, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.0313306674361, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.00162552122492, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.0594284757972, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.00252196309157, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.00824373029172, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-0.000259069609456, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.0148649141192, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-0.000303588982206, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.00894717965275, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(-9.83833451755e-05, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.0476220995188, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.0352777428925, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.0360622033477, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.0063727227971, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.00663845334202, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.0167386922985, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.0178248975426, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.0385978445411, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.0420189797878, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.0281181633472, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.0311955213547, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.0331449434161, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.0375955589116, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.0250437166542, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.0290441587567, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.0177368074656, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.0209663975984, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.00756648741663, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.00914631132036, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.00899442285299, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.0111190862954, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.00878779124469, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.0110755134374, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.0422141589224, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.0544221624732, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.0134133854881, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.0176907088608, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.0155342062935, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.0208939611912, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.0326513946056, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.0449407920241, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.0180661939085, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254498124123, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.004099923186, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.00589243136346, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.0343908704817, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.0506046302617, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.00291578890756, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00439360644668, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.00858093425632, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.0131983468309, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.0211385376751, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.0333090052009, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.012887166813, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0208091922104, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0140755902976, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.0232141204178, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.0127825895324, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.0216141790152, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.0200382247567, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.0347492285073, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.00618709856644, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.0109669007361, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(0.000456310808659, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(0.00083002448082, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.0284619033337, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.0531480312347, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.0238193273544, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.0455041266978, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.00929909106344, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.0182504933327, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126230288297, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254623964429, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.00197769422084, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.00408559478819, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.0172247961164, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.0366045534611, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.0187255777419, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.0409568548203, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.00829788390547, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.0186111200601, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.0151512529701, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.0350124835968, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.0142003111541, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.0338307842612, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.0241267420352, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.0590324029326, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.000959620811045, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.00242372602224, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.0239195413888, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.0624101832509, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.00083834445104, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.00225063227117, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.0158620364964, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.0440585017204, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.00656237127259, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.0188763812184, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.00519609684125, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.0154131874442, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.001888548024, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.00581235345453, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.0162148848176, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.0518368631601, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.00996446423233, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.0329415500164, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.0131337102503, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.0452065244317, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.0099840387702, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.0358312316239, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.00220311852172, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.00820496398956, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.00532320234925, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.020732505247, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.00263594370335, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.0107559524477, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.0182361342013, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.0775674432516, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.012164295651, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.0544199310243, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.00567965582013, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.0267896428704, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.00105418381281, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.0052140802145, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.00728108920157, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.0381688065827, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(6.25383108854e-07, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(3.48314642906e-06, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.00441306270659, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.0260087698698, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00902584567666, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.056986939162, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.0094291139394, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.0640860050917, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.00468873139471, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.0340957939625, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.0048383041285, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.0382991172373, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(0.000245103845373, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.002128129825, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(0.000327348709106, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.00309890322387, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.0016907810932, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.0178865995258, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.00530000776052, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.0635149255395, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(0.000551760895178, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.0074600726366, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.00113553181291, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.0180487614125, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.000905105960555, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.0174452140927, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.00306780124083, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.0722908079624, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.000848816183861, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.0270097702742, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.000977027928457, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.0478391423821, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(9.10624585231e-05, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.00828140322119, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.0720448940992, samples[301], epsilon);

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
  auto reference = renderMIDISequence(path, {{0, noteOnBytes(60)}, {60, noteOffBytes(60)}});
  auto tapped = renderMIDISequence(path, {{0, noteOnBytes(60)}, {10, sustainBytes(true)}, {20, sustainBytes(false)},
    {60, noteOffBytes(60)}});
  auto releasedAtTap = renderMIDISequence(path, {{0, noteOnBytes(60)}, {20, noteOffBytes(60)}});

  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertTrue(reference == tapped);

  // Guard against a vacuous test: releasing the note when the pedal lifts (the old behaviour) sounds different.
  XCTAssertFalse(reference == releasedAtTap);
}

- (void)testSustainPedalReleasesPostponedNoteWhenLifted
{
  // A note released while the sustain pedal is down keeps sounding until the pedal lifts. It then sounds exactly like a
  // note released at the time the pedal lifted.
  const auto path = self.contexts->context1.path();
  auto reference = renderMIDISequence(path, {{0, noteOnBytes(60)}, {40, noteOffBytes(60)}});
  auto sustained = renderMIDISequence(path, {{0, noteOnBytes(60)}, {5, sustainBytes(true)}, {20, noteOffBytes(60)},
    {40, sustainBytes(false)}});
  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertTrue(reference == sustained);
}

- (void)testSustainPedalLiftOnlyReleasesNotesWhoseKeysAreUp
{
  // Two notes under the sustain pedal: 60 is released while the pedal is down, 64 stays held. Lifting the pedal releases
  // 60 only. 64 sounds until its own note-off.
  const auto path = self.contexts->context1.path();
  auto reference = renderMIDISequence(path, {{0, noteOnBytes(60)}, {0, noteOnBytes(64)}, {30, noteOffBytes(60)},
    {60, noteOffBytes(64)}});
  auto sustained = renderMIDISequence(path, {{0, noteOnBytes(60)}, {0, noteOnBytes(64)}, {5, sustainBytes(true)},
    {15, noteOffBytes(60)}, {30, sustainBytes(false)}, {60, noteOffBytes(64)}});
  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertTrue(reference == sustained);
}

- (void)testSostenutoPedalHoldsOnlyCapturedNotes
{
  // 60 is down when sostenuto goes down, so it is captured. 64 starts afterwards and must release normally. 60 is
  // released while the pedal is down, so it sounds until the pedal lifts.
  const auto path = self.contexts->context1.path();
  auto reference = renderMIDISequence(path, {{0, noteOnBytes(60)}, {10, noteOnBytes(64)}, {20, noteOffBytes(64)},
    {40, noteOffBytes(60)}});
  auto held = renderMIDISequence(path, {{0, noteOnBytes(60)}, {5, sostenutoBytes(true)}, {10, noteOnBytes(64)},
    {20, noteOffBytes(64)}, {25, noteOffBytes(60)}, {40, sostenutoBytes(false)}});
  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertTrue(reference == held);
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
  XCTAssertTrue(reference == restored);
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
  std::vector<AUValue> samples(data, data + harness.duration());
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
    harness.sendNoteOn(64, 127);
    harness.renderToEnd(mixer);
    const AUValue* data = harness.dryBuffer().floatChannelData[0];
    return std::vector<AUValue>(data, data + harness.duration());
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
  auto reference = renderMIDISequence(path, {{0, noteOnBytes(60)}, {60, noteOffBytes(60)}});
  auto tapped = renderMIDISequence(path, {{0, noteOnBytes(60)}, {10, sostenutoBytes(true)},
    {20, sostenutoBytes(false)}, {60, noteOffBytes(60)}});
  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertTrue(reference == tapped);
}

@end
