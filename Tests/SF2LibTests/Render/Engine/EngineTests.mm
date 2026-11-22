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
  XCTAssertEqualWithAccuracy(0.0654087290168, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0352771133184, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0660912841558, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127437701449, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0485530756414, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.0664451271296, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.0342402942479, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.066093236208, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127317449078, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0485377162695, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0664517953992, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0342402942479, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.066093236208, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127317449078, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0485377162695, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.0664517953992, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0342402942479, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.066093236208, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127317449078, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0485377162695, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0664517953992, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0342402942479, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.066093236208, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127317449078, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.0485377162695, samples[24], epsilon);
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
  XCTAssertEqualWithAccuracy(0.0352703295648, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0660708844662, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(-0.0128065245226, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.048540763557, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.0664651989937, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.0342407040298, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0660937726498, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0128013445064, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0485254004598, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.066434584558, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0342336073518, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.0660726428032, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127857802436, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0485421009362, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.0664502009749, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0342287272215, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.066072627902, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127942692488, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0485253855586, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0664343088865, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0342623330653, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.0660935714841, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127312028781, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.0485171973705, samples[24], epsilon);
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
  harness.drainWorkQueue(); // the program change loads on the work queue
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
  XCTAssertEqualWithAccuracy(-0.027505710721, samples[1], self.epsilon);

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

  XCTAssertEqualWithAccuracy(-0.118740573525, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0550501719117, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0438617169857, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0183677896857, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00948761217296, samples[4], self.epsilon);

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

  XCTAssertEqualWithAccuracy(-0.0145150274038, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00936872698367, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00526821287349, samples[2], self.epsilon);

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

  XCTAssertEqualWithAccuracy(-0.00670631090179, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0404217392206, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0571596585214, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00669855577871, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0437088795006, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0235063321888, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000337353529176, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0209427885711, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0111733581871, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0111733581871, samples[9], self.epsilon);

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

  XCTAssertEqualWithAccuracy(-0.0529595948756, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0238527283072, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00398332299665, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000228972057812, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0239506103098, samples[4], self.epsilon);
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

  XCTAssertEqualWithAccuracy(-0.0529595948756, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0238527283072, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00384847167879, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0046416176483, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000240976689383, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00449384003878, samples[5], self.epsilon);

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
  XCTAssertEqualWithAccuracy(0.0433928892016, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0433928892016, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00469701364636, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00458042416722, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.00117827765644, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112049095333, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.0432310625911, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0402149856091, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.00628179125488, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.0056979781948, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0358480252326, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0317045040429, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.021457016468, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0185016002506, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0573151931167, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0494207926095, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0126037932932, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0105945952237, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0176002923399, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0144210699946, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0739481896162, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0592436790466, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0122983586043, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00960161909461, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.0134727638215, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.0102478098124, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.026986381039, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.0199980400503, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.0211245194077, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.0156541578472, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.0336715877056, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.0243025850505, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.0379603132606, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.0267681330442, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.0142886536196, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.0098083326593, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.0439970269799, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0293978750706, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.00887631811202, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.00577095802873, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.0143032921478, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.00904565956444, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.0364698581398, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.0230641998351, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.00715729594231, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.00441698543727, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.0434093885124, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.026041764766, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.0630744919181, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.0367698669434, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.00796417426318, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.00450893398374, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.00359371583909, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.00197566207498, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0219306796789, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.0117000564933, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.0164590552449, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.00878093391657, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.0446952618659, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.0232173297554, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.00312342634425, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.00157296971884, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00998344272375, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.00487140752375, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.00738088879734, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.00348735228181, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.0472697094083, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.021611828357, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.0252130590379, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.0111939553171, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.0191662944853, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.00850934628397, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.0712430849671, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.030564263463, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.0222929157317, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00923402793705, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.01340219751, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.00535507127643, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.0205186679959, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.00790009368211, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.00500115100294, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.00186289241537, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.00300713302568, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112013530452, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.0184735544026, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.00661812815815, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.0907716602087, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0312374718487, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.0151645522565, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.00500638969243, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.00834332033992, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.0026386459358, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.00999442487955, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.00302320555784, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.0251414533705, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.00730426609516, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.00240089744329, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(0.000698471441865, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.062116637826, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.0172031186521, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.0227930806577, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.0060058105737, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.0256924368441, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.00642489921302, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.00712646357715, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.00168725149706, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.0414608865976, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00933601055294, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.0180112943053, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.00381856365129, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.0479941889644, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.010175219737, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.0035308599472, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(0.000702331773937, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.0886122211814, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.0164713021368, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.023786585778, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.00411348696798, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.0306111313403, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.00494695687667, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.00867129396647, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.00128974532709, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.014341276139, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.00194948771968, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.00146823003888, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-0.000199556350708, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0598467923701, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00736946891993, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.00084288418293, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(9.30554233491e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(-0.000928074121475, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(-9.06714703888e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.0619621500373, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.00536650419235, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.00376983359456, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(0.000278823776171, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.00117035675794, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(7.13010667823e-05, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.0762947052717, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00467975018546, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.0313089378178, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.0015257850755, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.0594525411725, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.00214851577766, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.00824169069529, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-0.000207267992664, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.0148622412235, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-0.000186832068721, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.00898649543524, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.0476401336491, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.0356668159366, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.0356668159366, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.00642739329487, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.00659099593759, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.0168777350336, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.0177481621504, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.0388572365046, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.041771478951, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.0282170847058, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.0311081968248, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.0331850424409, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.037522058934, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254359524697, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.0287602264434, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.0179367084056, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.0208018887788, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.00764212943614, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.00909141264856, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.00906410720199, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.0110623519868, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.0088516511023, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.0110486652702, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.0423849225044, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.054289277643, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.0136702125892, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.0175096690655, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.0157870799303, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.020753543824, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.0330831930041, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.0446441546082, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.0182596389204, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.0252989940345, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.0041097253561, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.00582806952298, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.0346384607255, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.0504558458924, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.00297913560644, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00433953478932, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.00874900445342, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.0130938095972, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.0215217862278, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.0331026911736, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.0130889406428, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0206966586411, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0142524391413, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.0230946913362, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.0129111465067, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.0215217731893, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.0201719161123, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.0346032381058, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.00635553058237, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.0109023805708, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(0.00045882165432, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(0.000810299068689, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.0290445648134, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.0528306029737, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.024194361642, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.0453501008451, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.0094588380307, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.0182090383023, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127758281305, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.0253688097, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.00203267857432, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.00403626821935, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.0177477411926, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.0363721400499, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.0192238837481, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.0406868159771, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.00846408586949, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.0185127705336, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.0154770733789, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.0348602794111, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.0144540630281, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.0336913689971, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.0251430980861, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.0586067289114, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.000997572205961, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.0024083526805, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.0248108003289, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.0620942860842, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.000870807562023, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.00226144772023, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.0163334291428, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.0438489764929, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.006738783326, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.0188103467226, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.00547893531621, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.0152936652303, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.00198033917695, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.00575458491221, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.0170102119446, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.0515246093273, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.0103869028389, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.0328430756927, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.0136254038662, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.0450442656875, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.0103774126619, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.0357165113091, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.00227133091539, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.00820127129555, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.00570829724893, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.0206113904715, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.00281224213541, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.0106740780175, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.0193385817111, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.0773327797651, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.0128437997773, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.0542485043406, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.00601109676063, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.026695061475, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.00110938958824, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.00523274205625, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.00805893726647, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.0380121767521, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(-1.3645272702e-05, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(-6.85956329107e-05, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.00482716830447, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.0259691774845, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00983919017017, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.0569036155939, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.0103354984894, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.0639547333121, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.00507013965398, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.03408787027, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.00567821925506, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.0381761491299, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(0.000288506853394, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.00211662985384, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(0.000380842247978, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.00308546796441, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.00197292515077, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.0178705304861, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.0061973691918, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.0634336546063, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(0.000640412792563, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.00739426910877, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.00156044121832, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.0180127508938, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.00128594576381, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.0173866078258, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.00442596292123, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.0721571743488, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.00131240615156, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.0269304234535, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.00172833213583, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.0478406138718, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(0.000208125027712, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.00829900335521, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0.000905319000594, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.0720333009958, samples[301], epsilon);

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

  XCTAssertEqualWithAccuracy(0.0433928892016, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0433928892016, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00468981079757, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00458779558539, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.00117298401892, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112603046, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.0430410727859, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0404182597995, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.00624586595222, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.00573733588681, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.035547632724, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0320409536362, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.0212522856891, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.018736410886, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0573151931167, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0494207926095, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0125704482198, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0106341391802, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0175321400166, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.014503845945, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0736681893468, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0595914870501, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0122225675732, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.00969791226089, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.0133755756542, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.010374320671, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.0267648622394, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.0202935598791, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.0210999064147, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.0156873203814, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.0335950702429, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.0244082435966, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.0378760285676, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.0268872566521, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.0142267402261, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.00989790726453, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.0437647849321, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0297425147146, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.00882153585553, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.00585435796529, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.014188493602, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.0092246811837, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.0364335849881, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.0231214538217, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.00715035013855, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.00442822370678, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.0432861894369, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.0262460354716, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.062842220068, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.0371654555202, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.0079285139218, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.00457133632153, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.00357177387923, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.00201505655423, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0217819269747, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.0119747156277, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.0164452381432, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.00880677811801, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.044622104615, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.023357629776, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.00311597925611, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.00158767099492, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00995263736695, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.00493403896689, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.00734769087285, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.00355676095933, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.0470292195678, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.0221302695572, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.0250884536654, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.0114705041051, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.019152905792, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.00853944197297, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.0711467042565, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.0307879373431, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.0222491547465, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00933897867799, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.013359727338, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.00546016450971, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.0204432923347, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.00809310004115, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.00498337298632, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.00190994376317, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.00300713302568, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.00112013530452, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.0184631347656, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.00664713885635, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.0906730741262, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0315224826336, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.0151327997446, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.00510157132521, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.00832233857363, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.0027040920686, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.00996548868716, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.00311726541258, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.0250596180558, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.00758026447147, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.00240089744329, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(0.000698471441865, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.062089536339, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.0173006691039, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.0227645244449, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.00611316459253, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.025651562959, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.00658620148897, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.00711299199611, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.00174316926859, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.0413710586727, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.00972635112703, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.0179682187736, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.00401637284085, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.0479941889644, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.010175219737, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.00352863781154, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(0.000713420799002, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.0885336175561, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.0168886911124, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.0237602740526, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.00426288042217, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.030571334064, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.00518721994013, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.008658753708, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.0013714118395, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.0143189784139, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.00210707914084, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.00146791525185, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-0.000201862538233, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0598233491182, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00755744613707, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.000842435285449, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(9.7026117146e-05, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(-0.000927330926061, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(-9.79576725513e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.0619180910289, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.00585298240185, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.00376703962684, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(0.000314340693876, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.00116936117411, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(8.59026331455e-05, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.0762872546911, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00479958765209, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.031303986907, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.00162413716316, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.0594378709793, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.00252196309157, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.0082402266562, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-0.000259069609456, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.014860314317, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-0.000303588982206, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.00898595247418, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(-9.83833451755e-05, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.0476401336491, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.0352724939585, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.0360568314791, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.00637543015182, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.0066412743181, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.0167658887804, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.0178538560867, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.0385940112174, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.0420148000121, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.0281192176044, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.0311966929585, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.0331260599196, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.0375741422176, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.0250725410879, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.0290775895119, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.0177398622036, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.02097001113, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.0075704921037, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.00915115140378, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.00899442285299, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.0111190862954, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.00879948679358, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.0110902544111, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.0422141589224, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.0544221624732, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.0134213175625, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.0177011713386, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.0155579298735, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.0209258720279, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.0326609686017, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.0449539721012, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.0180603787303, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254416242242, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.00407302659005, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.00585377402604, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.0344003029168, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.0506185144186, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.00291060563177, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00438579451293, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.00858377572149, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.0132027156651, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.0211565084755, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.0333373248577, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.0128933005035, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0208190977573, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0140706142411, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.023205915466, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.0127756660804, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.0216024722904, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.0200086291879, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.0346979089081, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.00620077177882, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.0109911365435, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(0.000448601320386, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(0.000816002488136, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.0284619033337, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.0531467571855, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.0238374415785, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.0455387271941, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.00931553542614, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.0182827655226, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126161817461, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254485812038, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.00196903012693, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.00406769663095, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.017231784761, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.0366194024682, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.0187110919505, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.0409251749516, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.00828923471272, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.0185917224735, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.0151478415355, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.0350045934319, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.0141890086234, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.0338038541377, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.0241267420352, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.0590324029326, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.000959620811045, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.00242372602224, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.023930516094, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.0624388195574, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.000845888629556, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.0022708857432, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.0158503092825, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.0440259203315, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.00656120339409, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.0188730210066, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.0051897005178, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.015394218266, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.00188061641529, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.00578794255853, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.0161987990141, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.0517854429781, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.00997337512672, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.0329710096121, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.0131293023005, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.0451913587749, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.0099840387702, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.035828448832, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.00220684916712, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.00821885466576, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.00531879067421, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.0207153223455, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.00262739695609, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.0107210725546, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.0182434208691, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.0775984376669, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.012161096558, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.0544056147337, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.00567517150193, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.0267684906721, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.00106002436951, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.00524296611547, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.00728108920157, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.0381688065827, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(-1.23493373394e-05, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(-6.88396394253e-05, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.00441866600886, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.026041790843, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00903377775103, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.0570370219648, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.00943035632372, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.0640944540501, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.00469502434134, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.0341415554285, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.0048383041285, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.0382917746902, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(0.000245103845373, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.00212206412107, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(0.000327348709106, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.00309157371521, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.00169198343065, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.0178993139416, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.00530000776052, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.0635149255395, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(0.000547445612028, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.00740172713995, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.00113553181291, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.0180445052683, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.000903314095922, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.0174106806517, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.00306512671523, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.0722277760506, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.000846909009852, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.0269490797073, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.000977027928457, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.0478618741035, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(9.10624585231e-05, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.00830112397671, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.0720389857888, samples[301], epsilon);

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
  auto reference = renderMIDISequence(path, {{0, noteOnBytes(60)}, {5, sustainBytes(true)}, {20, noteOffBytes(60)},
    {40, sustainBytes(false)}});
  auto reset = renderMIDISequence(path, {{0, noteOnBytes(60)}, {5, sustainBytes(true)}, {20, noteOffBytes(60)},
    {40, resetAll}});
  XCTAssertGreaterThan(rms(reference, 0, reference.size()), 0.001);
  XCTAssertTrue(reference == reset);
}

- (void)testResetAllControllersKeepsHeldNotesSounding
{
  // A held note is unaffected by CC 121 when the controllers are already at their reset values.
  const auto path = self.contexts->context1.path();
  const std::array<uint8_t, 3> resetAll{0xB0, 121, 0};
  auto reference = renderMIDISequence(path, {{0, noteOnBytes(60)}, {60, noteOffBytes(60)}});
  auto reset = renderMIDISequence(path, {{0, noteOnBytes(60)}, {20, resetAll}, {60, noteOffBytes(60)}});
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
  auto centred = renderMIDISequence(path, {{0, noteOnBytes(60)}, {5, fullUp}, {30, centre}});
  auto reset = renderMIDISequence(path, {{0, noteOnBytes(60)}, {5, fullUp}, {30, resetAll}});
  XCTAssertTrue(centred == reset);

  // The bend range set with RPN 0 survives CC 121 (RP-015 keeps RPN values; it used to go back to 2 semitones).
  auto wide = renderMIDISequence(path, {{0, rpn0Msb}, {0, rpn0Lsb}, {0, twelveSemitones}, {0, noteOnBytes(60)},
    {20, fullUp}});
  auto wideAfterReset = renderMIDISequence(path, {{0, rpn0Msb}, {0, rpn0Lsb}, {0, twelveSemitones},
    {0, noteOnBytes(60)}, {10, resetAll}, {20, fullUp}});
  auto defaultRange = renderMIDISequence(path, {{0, noteOnBytes(60)}, {20, fullUp}});
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
    return std::vector<AUValue>(data, data + harness.duration());
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
    harness.drainWorkQueue(); // the program change loads on the work queue
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
