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
  XCTAssertEqualWithAccuracy(0.0585853196681, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.139635398984, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0656754374504, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.0630209818482, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0279885157943, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.0638590604067, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.136500775814, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0657718032598, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.0629670470953, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0279869697988, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0638560056686, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.136500775814, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.0657718032598, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(0.0629670470953, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0279869697988, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.0638560056686, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.136500775814, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0657718032598, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0629670470953, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0279869697988, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0638560056686, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.136500775814, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.0657718032598, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(0.0629670470953, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.0279869697988, samples[24], epsilon);
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
  XCTAssertEqualWithAccuracy(0.0584149733186, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.139659687877, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0654851198196, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.0635829642415, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(0.0277795381844, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(0.063857652247, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(0.13649687171, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0657718554139, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.0635389462113, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(0.0277802255005, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0636782422662, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.136522755027, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(0.0655816420913, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(0.063736461103, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(0.0279606021941, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(0.0638589933515, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.136534586549, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.0655846372247, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0635286420584, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0277778878808, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0636785924435, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.136495783925, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(0.0657671317458, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(0.062967300415, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(0.0278175324202, samples[24], epsilon);
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

  XCTAssertEqualWithAccuracy(0.00312164006755, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0297262258828, samples[1], self.epsilon);

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

  XCTAssertEqualWithAccuracy(-0.118135415018, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0529967471957, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0434629619122, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0186167340726, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00896860752255, samples[4], self.epsilon);

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
  XCTAssertEqualWithAccuracy(0.0427966490388, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0427966490388, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00298385135829, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00290978513658, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.001221338287, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.00116144027561, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.0451245233417, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0419763438404, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.00774562172592, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.00702576478943, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0370179265738, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.0327391773462, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.0218130685389, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0188086144626, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0554744303226, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0478335805237, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0115999616683, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00975078716874, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0192961730063, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0158106125891, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0745110064745, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0596945732832, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0128136631101, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0100039308891, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.0147891379893, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.0112499957904, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.0245529357344, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.0181947574019, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.0213920511305, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.0158524103463, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.0316022709012, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.0228090528399, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.0396750494838, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.0279773008078, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.0141653046012, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.00972462818027, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.0447442904115, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0298971813172, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.00921804830432, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.00599313434213, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.0138691989705, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.00877113267779, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.0356497578323, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.0225455500185, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.00802047923207, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.00494968192652, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.042154211551, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.0252887681127, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.0639647915959, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.0372882038355, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.00702556502074, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.00397811178118, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.00457188207656, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.00251341238618, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0213300213218, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.0113796042278, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.0184368826449, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.00983610935509, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.047466173768, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.024656701833, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.00362643646076, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.00182628724724, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00973296817392, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.00474918819964, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.00836042128503, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.00395016837865, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.0456253476441, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.0208600237966, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.0244988203049, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.0108768511564, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.0200138613582, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.00888564437628, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.0721704959869, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.0309621430933, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.0207972042263, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00861448422074, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.0146978702396, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.00587277906016, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.0206908732653, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.00796735286713, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.00515887979418, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.00192164583132, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.00234633777291, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.000873993849382, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.0192715264857, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.00690400134772, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.0900930836797, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0310039483011, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.0136409308761, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.00450338516384, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.0108055397868, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.00341734336689, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.00651739025488, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.00197143969126, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.0248427074403, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.00721747428179, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.00179400108755, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(0.000521205365658, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.0621681250632, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.0172173790634, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.0231419950724, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.00609709788114, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.0272309463471, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.00680963369086, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.0066657923162, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.00157818314619, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.0430325902998, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.0096899215132, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.0151845887303, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.00321927433833, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.0482024997473, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.0102193821222, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.000118385069072, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(2.35482584685e-05, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.0897194594145, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.0166771132499, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.0231939293444, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.00401045568287, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.0294039119035, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.00475186202675, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.00697847642004, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.00103796028998, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.0136556793004, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.00185602949932, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.00108428671956, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-0.000147372018546, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0617836341262, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00760796898976, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.00334990769625, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(0.000369833083823, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(0.000908009707928, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(8.87111527845e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.0585196092725, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.00506834778935, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.00531967543066, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(0.00039345305413, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.000776532106102, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(4.76309214719e-05, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.0778816267848, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00477708829567, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.02961018309, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.0014429994626, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.0608048774302, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.00219773408026, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.00710413046181, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-0.00017858389765, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.0140234883875, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-0.000176233646926, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.012026656419, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.0480893328786, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.0351785048842, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.0351785048842, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.00620440766215, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.00636233389378, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.0188958309591, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.0198703352362, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.0383193381131, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.0411932468414, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.0287419483066, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.031686834991, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.0318182818592, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.035976678133, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.026808835566, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.0303125362843, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.0172570757568, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.0200136937201, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.00776061415672, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.00923236459494, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.00863250624388, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.0105356015265, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.0096184052527, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.0120057314634, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.0430885776877, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.0551905594766, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.0137361064553, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.0175940729678, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.0160866826773, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.0211474001408, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.0341646447778, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.0461035184562, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.0183417275548, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.02541272901, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.00283080432564, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.00401441007853, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.034701552242, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.0505477525294, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.00230128597468, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00335215125233, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.00848249718547, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.0126949539408, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.0215703863651, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.0331774391234, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.0139339556918, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0220328252763, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0142113026232, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.0230280365795, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.0125452876091, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.0209119208157, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.0190015565604, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.0325955823064, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.00684344908223, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.0117393648252, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(5.27258962393e-05, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(9.31210815907e-05, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.0296784024686, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.0539848171175, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.0246474612504, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.0461993999779, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.0104050505906, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.0200305748731, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.0119800958782, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.0237887296826, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.00164349749684, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.00326347537339, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.0180678740144, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.0370282307267, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.0185255482793, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.0392088145018, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.00813145656139, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.0177852399647, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.015695258975, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.035351715982, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.0134321320802, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.031309325248, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.0251325927675, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.0585822463036, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.00161252822727, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.00389298610389, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.0254018735141, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.0635735690594, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.00108495308086, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.00281757768244, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.015893984586, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.0426692403853, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.00670431181788, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.0187141243368, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.00522612268105, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.0145879704505, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.00186779489741, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.00542754726484, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.0163002666086, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.0493741631508, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.010607149452, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.0335394963622, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.013658949174, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.0451551601291, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.0105934496969, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.0364628955722, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.0022827447392, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.00824248604476, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.0055069620721, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.0198844149709, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.00244611222297, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.00928440690041, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.01963512972, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.0785186439753, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.0128786694258, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.0543957836926, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.00597295723855, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.0265256874263, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.00131803774275, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.00621688552201, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.00762457121164, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.0359633713961, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(-0.00069403834641, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(-0.00348916649818, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.00503945257515, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.0271112229675, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.0100740734488, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.0582620315254, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.0103546865284, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.0640734732151, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.0054236613214, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.0364646911621, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.00559971667826, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.037648357451, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(0.000246085692197, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.00181056838483, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(0.000406154198572, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.00329834409058, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.00203332025558, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.0184175800532, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.0062271039933, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.0637380033731, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(0.000440955394879, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.00509130954742, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.00165839842521, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.0191480200738, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.00115781184286, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.0156541764736, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.00426163198426, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.0694780647755, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.00122436089441, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.0251237470657, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.00173002597876, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.0478647612035, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(0.000226668445976, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.00901695154607, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0.000909584574401, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.0723786279559, samples[301], epsilon);

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

  XCTAssertEqualWithAccuracy(0.0427966490388, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0427966490388, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.00297927483916, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(0.00291446782649, samples[3], epsilon);
  XCTAssertEqualWithAccuracy(-0.00121585186571, samples[4], epsilon);
  XCTAssertEqualWithAccuracy(-0.0011671828106, samples[5], epsilon);
  XCTAssertEqualWithAccuracy(-0.0449262112379, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(-0.0421885214746, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-0.0077013252303, samples[8], epsilon);
  XCTAssertEqualWithAccuracy(-0.00707429274917, samples[9], epsilon);
  XCTAssertEqualWithAccuracy(0.0367077291012, samples[10], epsilon);
  XCTAssertEqualWithAccuracy(0.03308660537, samples[11], epsilon);
  XCTAssertEqualWithAccuracy(-0.0216049421579, samples[12], epsilon);
  XCTAssertEqualWithAccuracy(-0.0190473198891, samples[13], epsilon);
  XCTAssertEqualWithAccuracy(-0.0554744303226, samples[14], epsilon);
  XCTAssertEqualWithAccuracy(-0.0478335805237, samples[15], epsilon);
  XCTAssertEqualWithAccuracy(0.0115692727268, samples[16], epsilon);
  XCTAssertEqualWithAccuracy(0.00978718139231, samples[17], epsilon);
  XCTAssertEqualWithAccuracy(0.0192214529961, samples[18], epsilon);
  XCTAssertEqualWithAccuracy(0.0159013681114, samples[19], epsilon);
  XCTAssertEqualWithAccuracy(0.0742288827896, samples[20], epsilon);
  XCTAssertEqualWithAccuracy(0.0600450336933, samples[21], epsilon);
  XCTAssertEqualWithAccuracy(-0.0127346981317, samples[22], epsilon);
  XCTAssertEqualWithAccuracy(-0.0101042585447, samples[23], epsilon);
  XCTAssertEqualWithAccuracy(-0.014682454057, samples[24], epsilon);
  XCTAssertEqualWithAccuracy(-0.0113888792694, samples[25], epsilon);
  XCTAssertEqualWithAccuracy(0.024351393804, samples[26], epsilon);
  XCTAssertEqualWithAccuracy(0.0184636246413, samples[27], epsilon);
  XCTAssertEqualWithAccuracy(-0.0213671252131, samples[28], epsilon);
  XCTAssertEqualWithAccuracy(-0.0158859919757, samples[29], epsilon);
  XCTAssertEqualWithAccuracy(-0.0315304547548, samples[30], epsilon);
  XCTAssertEqualWithAccuracy(-0.022908218205, samples[31], epsilon);
  XCTAssertEqualWithAccuracy(-0.0395869612694, samples[32], epsilon);
  XCTAssertEqualWithAccuracy(-0.0281018055975, samples[33], epsilon);
  XCTAssertEqualWithAccuracy(0.0141039239243, samples[34], epsilon);
  XCTAssertEqualWithAccuracy(0.00981343816966, samples[35], epsilon);
  XCTAssertEqualWithAccuracy(0.0445081032813, samples[36], epsilon);
  XCTAssertEqualWithAccuracy(0.0302476752549, samples[37], epsilon);
  XCTAssertEqualWithAccuracy(-0.00916115567088, samples[38], epsilon);
  XCTAssertEqualWithAccuracy(-0.00607974547893, samples[39], epsilon);
  XCTAssertEqualWithAccuracy(0.0137578863651, samples[40], epsilon);
  XCTAssertEqualWithAccuracy(0.00894472096115, samples[41], epsilon);
  XCTAssertEqualWithAccuracy(0.0356142967939, samples[42], epsilon);
  XCTAssertEqualWithAccuracy(0.0226015206426, samples[43], epsilon);
  XCTAssertEqualWithAccuracy(0.00801269523799, samples[44], epsilon);
  XCTAssertEqualWithAccuracy(0.00496227433905, samples[45], epsilon);
  XCTAssertEqualWithAccuracy(0.042034573853, samples[46], epsilon);
  XCTAssertEqualWithAccuracy(0.0254871342331, samples[47], epsilon);
  XCTAssertEqualWithAccuracy(-0.0637292414904, samples[48], epsilon);
  XCTAssertEqualWithAccuracy(-0.0376893691719, samples[49], epsilon);
  XCTAssertEqualWithAccuracy(0.00699410587549, samples[50], epsilon);
  XCTAssertEqualWithAccuracy(0.00403316691518, samples[51], epsilon);
  XCTAssertEqualWithAccuracy(-0.004543970339, samples[52], epsilon);
  XCTAssertEqualWithAccuracy(-0.00256353034638, samples[53], epsilon);
  XCTAssertEqualWithAccuracy(-0.0211853403598, samples[54], epsilon);
  XCTAssertEqualWithAccuracy(-0.0116467401385, samples[55], epsilon);
  XCTAssertEqualWithAccuracy(-0.018421407789, samples[56], epsilon);
  XCTAssertEqualWithAccuracy(-0.00986505672336, samples[57], epsilon);
  XCTAssertEqualWithAccuracy(-0.0473884791136, samples[58], epsilon);
  XCTAssertEqualWithAccuracy(-0.0248056985438, samples[59], epsilon);
  XCTAssertEqualWithAccuracy(0.00361778982915, samples[60], epsilon);
  XCTAssertEqualWithAccuracy(0.00184335652739, samples[61], epsilon);
  XCTAssertEqualWithAccuracy(0.00970293488353, samples[62], epsilon);
  XCTAssertEqualWithAccuracy(0.0048102485016, samples[63], epsilon);
  XCTAssertEqualWithAccuracy(0.00832282006741, samples[64], epsilon);
  XCTAssertEqualWithAccuracy(0.00402878597379, samples[65], epsilon);
  XCTAssertEqualWithAccuracy(0.0453932285309, samples[66], epsilon);
  XCTAssertEqualWithAccuracy(0.0213604308665, samples[67], epsilon);
  XCTAssertEqualWithAccuracy(-0.0243777446449, samples[68], epsilon);
  XCTAssertEqualWithAccuracy(-0.0111455665901, samples[69], epsilon);
  XCTAssertEqualWithAccuracy(-0.0199998803437, samples[70], epsilon);
  XCTAssertEqualWithAccuracy(-0.00891707092524, samples[71], epsilon);
  XCTAssertEqualWithAccuracy(-0.0720728710294, samples[72], epsilon);
  XCTAssertEqualWithAccuracy(-0.0311887171119, samples[73], epsilon);
  XCTAssertEqualWithAccuracy(-0.0207563787699, samples[74], epsilon);
  XCTAssertEqualWithAccuracy(-0.00871239230037, samples[75], epsilon);
  XCTAssertEqualWithAccuracy(0.0146512947977, samples[76], epsilon);
  XCTAssertEqualWithAccuracy(0.00598803348839, samples[77], epsilon);
  XCTAssertEqualWithAccuracy(-0.0206148661673, samples[78], epsilon);
  XCTAssertEqualWithAccuracy(-0.00816200207919, samples[79], epsilon);
  XCTAssertEqualWithAccuracy(0.0051405383274, samples[80], epsilon);
  XCTAssertEqualWithAccuracy(0.00197018077597, samples[81], epsilon);
  XCTAssertEqualWithAccuracy(-0.00234633777291, samples[82], epsilon);
  XCTAssertEqualWithAccuracy(-0.000873993849382, samples[83], epsilon);
  XCTAssertEqualWithAccuracy(0.0192606598139, samples[84], epsilon);
  XCTAssertEqualWithAccuracy(0.00693426374346, samples[85], epsilon);
  XCTAssertEqualWithAccuracy(0.0899952352047, samples[86], epsilon);
  XCTAssertEqualWithAccuracy(0.0312868319452, samples[87], epsilon);
  XCTAssertEqualWithAccuracy(-0.0136123653501, samples[88], epsilon);
  XCTAssertEqualWithAccuracy(-0.00458900304511, samples[89], epsilon);
  XCTAssertEqualWithAccuracy(-0.0107783675194, samples[90], epsilon);
  XCTAssertEqualWithAccuracy(-0.00350210350007, samples[91], epsilon);
  XCTAssertEqualWithAccuracy(0.00649852119386, samples[92], epsilon);
  XCTAssertEqualWithAccuracy(0.00203277659602, samples[93], epsilon);
  XCTAssertEqualWithAccuracy(-0.0247618481517, samples[94], epsilon);
  XCTAssertEqualWithAccuracy(-0.00749019207433, samples[95], epsilon);
  XCTAssertEqualWithAccuracy(0.00179400108755, samples[96], epsilon);
  XCTAssertEqualWithAccuracy(0.000521205365658, samples[97], epsilon);
  XCTAssertEqualWithAccuracy(-0.0621410012245, samples[98], epsilon);
  XCTAssertEqualWithAccuracy(-0.0173150114715, samples[99], epsilon);
  XCTAssertEqualWithAccuracy(0.0231130067259, samples[100], epsilon);
  XCTAssertEqualWithAccuracy(0.00620608357713, samples[101], epsilon);
  XCTAssertEqualWithAccuracy(0.0271876230836, samples[102], epsilon);
  XCTAssertEqualWithAccuracy(0.0069805951789, samples[103], epsilon);
  XCTAssertEqualWithAccuracy(0.00665318965912, samples[104], epsilon);
  XCTAssertEqualWithAccuracy(0.00163048692048, samples[105], epsilon);
  XCTAssertEqualWithAccuracy(0.0429393537343, samples[106], epsilon);
  XCTAssertEqualWithAccuracy(0.0100950561464, samples[107], epsilon);
  XCTAssertEqualWithAccuracy(0.0151482708752, samples[108], epsilon);
  XCTAssertEqualWithAccuracy(0.00338603975251, samples[109], epsilon);
  XCTAssertEqualWithAccuracy(0.0482024997473, samples[110], epsilon);
  XCTAssertEqualWithAccuracy(0.0102193821222, samples[111], epsilon);
  XCTAssertEqualWithAccuracy(0.000118311494589, samples[112], epsilon);
  XCTAssertEqualWithAccuracy(2.39200890064e-05, samples[113], epsilon);
  XCTAssertEqualWithAccuracy(-0.0896398723125, samples[114], epsilon);
  XCTAssertEqualWithAccuracy(-0.0170997194946, samples[115], epsilon);
  XCTAssertEqualWithAccuracy(-0.0231682732701, samples[116], epsilon);
  XCTAssertEqualWithAccuracy(-0.00415610801429, samples[117], epsilon);
  XCTAssertEqualWithAccuracy(-0.0293656848371, samples[118], epsilon);
  XCTAssertEqualWithAccuracy(-0.00498265121132, samples[119], epsilon);
  XCTAssertEqualWithAccuracy(-0.00696838460863, samples[120], epsilon);
  XCTAssertEqualWithAccuracy(-0.00110368360765, samples[121], epsilon);
  XCTAssertEqualWithAccuracy(-0.0136344507337, samples[122], epsilon);
  XCTAssertEqualWithAccuracy(-0.00200606603175, samples[123], epsilon);
  XCTAssertEqualWithAccuracy(-0.00108405388892, samples[124], epsilon);
  XCTAssertEqualWithAccuracy(-0.000149075174704, samples[125], epsilon);
  XCTAssertEqualWithAccuracy(0.0617594271898, samples[126], epsilon);
  XCTAssertEqualWithAccuracy(0.00780203007162, samples[127], epsilon);
  XCTAssertEqualWithAccuracy(0.00334812700748, samples[128], epsilon);
  XCTAssertEqualWithAccuracy(0.000385615276173, samples[129], epsilon);
  XCTAssertEqualWithAccuracy(0.000907285138965, samples[130], epsilon);
  XCTAssertEqualWithAccuracy(9.58399032243e-05, samples[131], epsilon);
  XCTAssertEqualWithAccuracy(0.0584779977798, samples[132], epsilon);
  XCTAssertEqualWithAccuracy(0.00552779855207, samples[133], epsilon);
  XCTAssertEqualWithAccuracy(0.00531573034823, samples[134], epsilon);
  XCTAssertEqualWithAccuracy(0.000443571479991, samples[135], epsilon);
  XCTAssertEqualWithAccuracy(0.000775873661041, samples[136], epsilon);
  XCTAssertEqualWithAccuracy(5.73849538341e-05, samples[137], epsilon);
  XCTAssertEqualWithAccuracy(-0.0778740271926, samples[138], epsilon);
  XCTAssertEqualWithAccuracy(-0.00489941798151, samples[139], epsilon);
  XCTAssertEqualWithAccuracy(-0.0296055078506, samples[140], epsilon);
  XCTAssertEqualWithAccuracy(-0.00153601518832, samples[141], epsilon);
  XCTAssertEqualWithAccuracy(0.0607898682356, samples[142], epsilon);
  XCTAssertEqualWithAccuracy(0.00257973652333, samples[143], epsilon);
  XCTAssertEqualWithAccuracy(-0.0071028675884, samples[144], epsilon);
  XCTAssertEqualWithAccuracy(-0.000223216658924, samples[145], epsilon);
  XCTAssertEqualWithAccuracy(-0.0140216723084, samples[146], epsilon);
  XCTAssertEqualWithAccuracy(-0.000286367285298, samples[147], epsilon);
  XCTAssertEqualWithAccuracy(-0.0120259281248, samples[148], epsilon);
  XCTAssertEqualWithAccuracy(-0.000132237313665, samples[149], epsilon);
  XCTAssertEqualWithAccuracy(0.0480893328786, samples[150], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[151], epsilon);
  XCTAssertEqualWithAccuracy(0.0347895808518, samples[152], epsilon);
  XCTAssertEqualWithAccuracy(0.0355631783605, samples[153], epsilon);
  XCTAssertEqualWithAccuracy(0.00615424616262, samples[154], epsilon);
  XCTAssertEqualWithAccuracy(0.00641086604446, samples[155], epsilon);
  XCTAssertEqualWithAccuracy(-0.018770609051, samples[156], epsilon);
  XCTAssertEqualWithAccuracy(-0.0199886690825, samples[157], epsilon);
  XCTAssertEqualWithAccuracy(0.0380597598851, samples[158], epsilon);
  XCTAssertEqualWithAccuracy(0.0414331965148, samples[159], epsilon);
  XCTAssertEqualWithAccuracy(-0.0286422595382, samples[160], epsilon);
  XCTAssertEqualWithAccuracy(-0.0317769758403, samples[161], epsilon);
  XCTAssertEqualWithAccuracy(-0.0317617319524, samples[162], epsilon);
  XCTAssertEqualWithAccuracy(-0.0360266119242, samples[163], epsilon);
  XCTAssertEqualWithAccuracy(-0.0264258105308, samples[164], epsilon);
  XCTAssertEqualWithAccuracy(-0.0306470226496, samples[165], epsilon);
  XCTAssertEqualWithAccuracy(0.0170676913112, samples[166], epsilon);
  XCTAssertEqualWithAccuracy(0.0201754458249, samples[167], epsilon);
  XCTAssertEqualWithAccuracy(0.00768786389381, samples[168], epsilon);
  XCTAssertEqualWithAccuracy(0.00929303187877, samples[169], epsilon);
  XCTAssertEqualWithAccuracy(-0.00856613926589, samples[170], epsilon);
  XCTAssertEqualWithAccuracy(-0.010589633137, samples[171], epsilon);
  XCTAssertEqualWithAccuracy(-0.00956172309816, samples[172], epsilon);
  XCTAssertEqualWithAccuracy(-0.01205092296, samples[173], epsilon);
  XCTAssertEqualWithAccuracy(0.0429149791598, samples[174], epsilon);
  XCTAssertEqualWithAccuracy(0.0553256571293, samples[175], epsilon);
  XCTAssertEqualWithAccuracy(0.0134860118851, samples[176], epsilon);
  XCTAssertEqualWithAccuracy(0.0177864953876, samples[177], epsilon);
  XCTAssertEqualWithAccuracy(0.0158531889319, samples[178], epsilon);
  XCTAssertEqualWithAccuracy(0.0213230028749, samples[179], epsilon);
  XCTAssertEqualWithAccuracy(-0.0337286181748, samples[180], epsilon);
  XCTAssertEqualWithAccuracy(-0.0464234612882, samples[181], epsilon);
  XCTAssertEqualWithAccuracy(-0.0181415714324, samples[182], epsilon);
  XCTAssertEqualWithAccuracy(-0.0255559999496, samples[183], epsilon);
  XCTAssertEqualWithAccuracy(0.00280552636832, samples[184], epsilon);
  XCTAssertEqualWithAccuracy(0.00403211638331, samples[185], epsilon);
  XCTAssertEqualWithAccuracy(-0.0344629660249, samples[186], epsilon);
  XCTAssertEqualWithAccuracy(-0.0507107153535, samples[187], epsilon);
  XCTAssertEqualWithAccuracy(-0.00224834913388, samples[188], epsilon);
  XCTAssertEqualWithAccuracy(-0.00338788516819, samples[189], epsilon);
  XCTAssertEqualWithAccuracy(-0.00832230225205, samples[190], epsilon);
  XCTAssertEqualWithAccuracy(-0.0128005445004, samples[191], epsilon);
  XCTAssertEqualWithAccuracy(0.021204283461, samples[192], epsilon);
  XCTAssertEqualWithAccuracy(0.0334126055241, samples[193], epsilon);
  XCTAssertEqualWithAccuracy(0.0137256868184, samples[194], epsilon);
  XCTAssertEqualWithAccuracy(0.0221631694585, samples[195], epsilon);
  XCTAssertEqualWithAccuracy(-0.0140300039202, samples[196], epsilon);
  XCTAssertEqualWithAccuracy(-0.0231389403343, samples[197], epsilon);
  XCTAssertEqualWithAccuracy(0.0124136479571, samples[198], epsilon);
  XCTAssertEqualWithAccuracy(0.0209903307259, samples[199], epsilon);
  XCTAssertEqualWithAccuracy(0.0188477411866, samples[200], epsilon);
  XCTAssertEqualWithAccuracy(0.0326847583055, samples[201], epsilon);
  XCTAssertEqualWithAccuracy(0.00667680986226, samples[202], epsilon);
  XCTAssertEqualWithAccuracy(0.0118349343538, samples[203], epsilon);
  XCTAssertEqualWithAccuracy(5.15524297953e-05, samples[204], epsilon);
  XCTAssertEqualWithAccuracy(9.37730073929e-05, samples[205], epsilon);
  XCTAssertEqualWithAccuracy(-0.0290830265731, samples[206], epsilon);
  XCTAssertEqualWithAccuracy(-0.0543078780174, samples[207], epsilon);
  XCTAssertEqualWithAccuracy(0.0242838561535, samples[208], epsilon);
  XCTAssertEqualWithAccuracy(0.0463915541768, samples[209], epsilon);
  XCTAssertEqualWithAccuracy(-0.0102474112064, samples[210], epsilon);
  XCTAssertEqualWithAccuracy(-0.0201116763055, samples[211], epsilon);
  XCTAssertEqualWithAccuracy(-0.011830390431, samples[212], epsilon);
  XCTAssertEqualWithAccuracy(-0.0238635335118, samples[213], epsilon);
  XCTAssertEqualWithAccuracy(0.00159203447402, samples[214], epsilon);
  XCTAssertEqualWithAccuracy(0.00328888744116, samples[215], epsilon);
  XCTAssertEqualWithAccuracy(0.0175426118076, samples[216], epsilon);
  XCTAssertEqualWithAccuracy(0.0372799411416, samples[217], epsilon);
  XCTAssertEqualWithAccuracy(0.0180313885212, samples[218], epsilon);
  XCTAssertEqualWithAccuracy(0.0394385121763, samples[219], epsilon);
  XCTAssertEqualWithAccuracy(0.00796347577125, samples[220], epsilon);
  XCTAssertEqualWithAccuracy(0.0178610850126, samples[221], epsilon);
  XCTAssertEqualWithAccuracy(-0.0153613835573, samples[222], epsilon);
  XCTAssertEqualWithAccuracy(-0.0354980677366, samples[223], epsilon);
  XCTAssertEqualWithAccuracy(0.0131858177483, samples[224], epsilon);
  XCTAssertEqualWithAccuracy(0.0314138531685, samples[225], epsilon);
  XCTAssertEqualWithAccuracy(-0.0241166632622, samples[226], epsilon);
  XCTAssertEqualWithAccuracy(-0.0590077415109, samples[227], epsilon);
  XCTAssertEqualWithAccuracy(0.00155118014663, samples[228], epsilon);
  XCTAssertEqualWithAccuracy(0.00391783379018, samples[229], epsilon);
  XCTAssertEqualWithAccuracy(-0.0245006158948, samples[230], epsilon);
  XCTAssertEqualWithAccuracy(-0.0639263093472, samples[231], epsilon);
  XCTAssertEqualWithAccuracy(-0.0010539079085, samples[232], epsilon);
  XCTAssertEqualWithAccuracy(-0.00282933749259, samples[233], epsilon);
  XCTAssertEqualWithAccuracy(0.0154238604009, samples[234], epsilon);
  XCTAssertEqualWithAccuracy(0.0428414233029, samples[235], epsilon);
  XCTAssertEqualWithAccuracy(-0.00652764039114, samples[236], epsilon);
  XCTAssertEqualWithAccuracy(-0.0187764801085, samples[237], epsilon);
  XCTAssertEqualWithAccuracy(-0.00495023373514, samples[238], epsilon);
  XCTAssertEqualWithAccuracy(-0.0146838836372, samples[239], epsilon);
  XCTAssertEqualWithAccuracy(0.00177373969927, samples[240], epsilon);
  XCTAssertEqualWithAccuracy(0.00545900780708, samples[241], epsilon);
  XCTAssertEqualWithAccuracy(0.0155227202922, samples[242], epsilon);
  XCTAssertEqualWithAccuracy(0.0496241040528, samples[243], epsilon);
  XCTAssertEqualWithAccuracy(0.0101848524064, samples[244], epsilon);
  XCTAssertEqualWithAccuracy(0.0336701348424, samples[245], epsilon);
  XCTAssertEqualWithAccuracy(-0.0131616266444, samples[246], epsilon);
  XCTAssertEqualWithAccuracy(-0.0453026145697, samples[247], epsilon);
  XCTAssertEqualWithAccuracy(-0.0101918876171, samples[248], epsilon);
  XCTAssertEqualWithAccuracy(-0.0365771725774, samples[249], epsilon);
  XCTAssertEqualWithAccuracy(-0.00221793935634, samples[250], epsilon);
  XCTAssertEqualWithAccuracy(-0.0082601569593, samples[251], epsilon);
  XCTAssertEqualWithAccuracy(-0.00513119343668, samples[252], epsilon);
  XCTAssertEqualWithAccuracy(-0.0199846792966, samples[253], epsilon);
  XCTAssertEqualWithAccuracy(0.0022853333503, samples[254], epsilon);
  XCTAssertEqualWithAccuracy(0.00932528451085, samples[255], epsilon);
  XCTAssertEqualWithAccuracy(-0.0185231752694, samples[256], epsilon);
  XCTAssertEqualWithAccuracy(-0.078788369894, samples[257], epsilon);
  XCTAssertEqualWithAccuracy(0.0121941119432, samples[258], epsilon);
  XCTAssertEqualWithAccuracy(0.054553322494, samples[259], epsilon);
  XCTAssertEqualWithAccuracy(0.00563916284591, samples[260], epsilon);
  XCTAssertEqualWithAccuracy(0.0265986509621, samples[261], epsilon);
  XCTAssertEqualWithAccuracy(0.00125938816927, samples[262], epsilon);
  XCTAssertEqualWithAccuracy(0.00622903183103, samples[263], epsilon);
  XCTAssertEqualWithAccuracy(0.00688864756376, samples[264], epsilon);
  XCTAssertEqualWithAccuracy(0.0361115559936, samples[265], epsilon);
  XCTAssertEqualWithAccuracy(-0.000628149136901, samples[266], epsilon);
  XCTAssertEqualWithAccuracy(-0.00350162573159, samples[267], epsilon);
  XCTAssertEqualWithAccuracy(-0.00461298646405, samples[268], epsilon);
  XCTAssertEqualWithAccuracy(-0.0271870363504, samples[269], epsilon);
  XCTAssertEqualWithAccuracy(-0.00924943387508, samples[270], epsilon);
  XCTAssertEqualWithAccuracy(-0.05839863047, samples[271], epsilon);
  XCTAssertEqualWithAccuracy(-0.0094478642568, samples[272], epsilon);
  XCTAssertEqualWithAccuracy(-0.0642134472728, samples[273], epsilon);
  XCTAssertEqualWithAccuracy(0.00502239121124, samples[274], epsilon);
  XCTAssertEqualWithAccuracy(0.0365221202374, samples[275], epsilon);
  XCTAssertEqualWithAccuracy(-0.00477049872279, samples[276], epsilon);
  XCTAssertEqualWithAccuracy(-0.0377623848617, samples[277], epsilon);
  XCTAssertEqualWithAccuracy(0.000209064455703, samples[278], epsilon);
  XCTAssertEqualWithAccuracy(0.00181521475315, samples[279], epsilon);
  XCTAssertEqualWithAccuracy(0.000349105335772, samples[280], epsilon);
  XCTAssertEqualWithAccuracy(0.00330486707389, samples[281], epsilon);
  XCTAssertEqualWithAccuracy(0.00174377812073, samples[282], epsilon);
  XCTAssertEqualWithAccuracy(0.0184472464025, samples[283], epsilon);
  XCTAssertEqualWithAccuracy(0.0053254365921, samples[284], epsilon);
  XCTAssertEqualWithAccuracy(0.0638196617365, samples[285], epsilon);
  XCTAssertEqualWithAccuracy(0.000376942800358, samples[286], epsilon);
  XCTAssertEqualWithAccuracy(0.00509645044804, samples[287], epsilon);
  XCTAssertEqualWithAccuracy(-0.00120681500994, samples[288], epsilon);
  XCTAssertEqualWithAccuracy(-0.0191817749292, samples[289], epsilon);
  XCTAssertEqualWithAccuracy(0.00081330636749, samples[290], epsilon);
  XCTAssertEqualWithAccuracy(0.0156758502126, samples[291], epsilon);
  XCTAssertEqualWithAccuracy(-0.00295132212341, samples[292], epsilon);
  XCTAssertEqualWithAccuracy(-0.0695460438728, samples[293], epsilon);
  XCTAssertEqualWithAccuracy(-0.000790092512034, samples[294], epsilon);
  XCTAssertEqualWithAccuracy(-0.0251411497593, samples[295], epsilon);
  XCTAssertEqualWithAccuracy(-0.000977985560894, samples[296], epsilon);
  XCTAssertEqualWithAccuracy(-0.0478860288858, samples[297], epsilon);
  XCTAssertEqualWithAccuracy(9.91758861346e-05, samples[298], epsilon);
  XCTAssertEqualWithAccuracy(0.00901925563812, samples[299], epsilon);
  XCTAssertEqualWithAccuracy(0, samples[300], epsilon);
  XCTAssertEqualWithAccuracy(0.0723843425512, samples[301], epsilon);

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

@end
