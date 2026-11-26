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

struct LiveAttenuationResult {
  double before;
  double after;
  size_t activeVoiceCount;
};

/// Render a held, looped note before and after a live controller or parameter change.
template <typename Change>
static LiveAttenuationResult renderLiveAttenuationChange(const std::string& path, Change change)
{
  constexpr AVAudioFrameCount blocksPerHalf = 10;
  auto harness{TestEngineHarness{48000.0}};
  if (harness.load(path, 0) != IO::File::LoadResponse::ok) return {};
  harness.setParameter(Index::delayVolumeEnvelope, -12'000);
  harness.setParameter(Index::attackVolumeEnvelope, -12'000);
  harness.setParameter(Index::holdVolumeEnvelope, -12'000);
  harness.setParameter(Index::decayVolumeEnvelope, -12'000);
  harness.setParameter(Index::sustainVolumeEnvelope, 0);
  harness.setParameter(Index::modulatorLFOToVolume, 0);
  auto mixer{harness.createMixer(double(2 * blocksPerHalf * harness.maxFramesToRender()) / 48'000.0)};
  harness.sendNoteOn(69, 127);
  harness.renderMaxFramesCount(mixer, blocksPerHalf);
  change(harness);
  harness.renderMaxFramesCount(mixer, blocksPerHalf);

  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  std::vector<AUValue> samples(data, data + harness.bufferFrameCount());
  auto half = size_t(blocksPerHalf * harness.maxFramesToRender());
  auto window = size_t(5 * harness.maxFramesToRender());
  return {rms(samples, half - window, half), rms(samples, 2 * half - window, 2 * half),
          harness.engine().activeVoiceCount()};
}

@interface EngineTests : SamplePlayingTestCase
@end

@implementation EngineTests

- (void)setUp {
  [super setUp];
  // self.playAudio = true;
}

- (void)testInit {
  Engine engine;
  XCTAssertEqual(engine.maxVoiceCount(), size_t(128));
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
  auto& engine{harness.engine()};

  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());

  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 1.0);
  XCTAssertTrue(engine.oneVoicePerKeyModeEnabled());

  harness.setParameter(ParameterAddress::oneVoicePerKeyModeEnabled, 0.0);
  XCTAssertFalse(engine.oneVoicePerKeyModeEnabled());
}

- (void)testRetriggering {
  auto harness{TestEngineHarness{}};
  auto& engine{harness.engine()};

  XCTAssertTrue(engine.retriggerModeEnabled());

  harness.setParameter(ParameterAddress::retriggerModeEnabled, 0.0);
  XCTAssertFalse(engine.retriggerModeEnabled());

  harness.setParameter(ParameterAddress::retriggerModeEnabled, 1.0);
  XCTAssertTrue(engine.retriggerModeEnabled());
}

- (void)testLoad {
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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

- (void)testRolandPianoChordRenderCubic4thOrder {
  auto harness{TestEngineHarness{}};
  harness.setRenderingTimeBudgetScaling(-1.0);
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
  XCTAssertEqualWithAccuracy(0.039129, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.059538, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.040952, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.062327, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022343, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.035629, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.056754, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.039886, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.061996, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022218, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.035579, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.056758, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(0.039888, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(0.061996, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022218, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(0.035579, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.056758, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.039888, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.061996, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022218, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(0.035579, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(0.056758, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(0.039888, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(0.061996, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022218, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[25], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineMIDIProgramChange {
  auto harness{TestEngineHarness{}};
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

  XCTAssertEqualWithAccuracy(0.005160, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004066, samples[1], self.epsilon);

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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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

  XCTAssertEqualWithAccuracy(0.132158, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.053145, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.006965, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.010662, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.002302, samples[4], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineExcludeClassNoteTermination
{
  // SF2.01 8.1.2 #57: a new note with the same exclusiveClass "rapidly terminates" a sounding one. Use a ~5 ms release
  // rather than a hard cut: the old voice must still be fading after 1 ms and gone after 6 ms. It actually stops after
  // about 2 ms, because its gain (which includes the velocity attenuation) drops below the -80 dB cut-off early.
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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

  XCTAssertEqualWithAccuracy(0.007683, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.017845, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.006056, samples[2], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineMIDIKeyPressure // no effect as there is no modulator using it
{
  auto harness{TestEngineHarness{}};
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

  XCTAssertEqualWithAccuracy(-0.055174, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.126231, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.024512, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.097875, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.068169, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.016668, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.070357, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.066461, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.052915, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.014250, samples[9], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineSustainPedalProcessing
{
  auto harness{TestEngineHarness{}};
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

  XCTAssertEqualWithAccuracy(0.071227, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.009531, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.012803, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.002166, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.071308, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.001850, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[6], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineSostenutoPedalProcessing
{
  auto harness{TestEngineHarness{}};
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

  XCTAssertEqualWithAccuracy(0.079032, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.071227, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.019970, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.064721, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.002118, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.003020, samples[5], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineMIDIControlChangeCC10ForPanning
{
  auto harness{TestEngineHarness{}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 18);

  int seconds = 4;
  auto mixer{harness.createMixer(seconds)};

  harness.sendNoteOn(60);
  harness.sendNoteOn(64);
  harness.sendNoteOn(67);
  harness.renderMaxFramesCount(mixer);

  std::vector<AUValue> samples;
  // samples.reserve(374);
  samples.push_back(harness.lastDrySample(0));
  samples.push_back(harness.lastDrySample(1));

  AUMIDIEvent midiEvent;
  midiEvent.data[0] = DSPHeaders::valueOf(MIDI::CoreEvent::controlChange);
  midiEvent.data[1] = 10;
  midiEvent.data[2] = 0;
  midiEvent.length = 3;

  // Pan left
  auto steps = harness.engine().sampleRate() / harness.maxFramesToRender();
  auto sampleIndex = 0;
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = uint8_t(64 - (step / steps * 64));
    engine.doMIDIEvent(midiEvent);
    harness.renderMaxFramesCount(mixer);
    if ((sampleIndex++ % 20) == 0) {
      samples.push_back(harness.lastDrySample(0));
      samples.push_back(harness.lastDrySample(1));
    }
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = uint8_t(64 - (step / steps * 64));
    engine.doMIDIEvent(midiEvent);
    harness.renderMaxFramesCount(mixer);
    if ((sampleIndex++ % 20) == 0) {
      samples.push_back(harness.lastDrySample(0));
      samples.push_back(harness.lastDrySample(1));
    }
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    midiEvent.data[2] = uint8_t(64 + (step / steps * 63));
    engine.doMIDIEvent(midiEvent);
    harness.renderMaxFramesCount(mixer);
    if ((sampleIndex++ % 20) == 0) {
      samples.push_back(harness.lastDrySample(0));
      samples.push_back(harness.lastDrySample(1));
    }
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    midiEvent.data[2] = uint8_t(64 + (step / steps * 63));
    engine.doMIDIEvent(midiEvent);
    harness.renderMaxFramesCount(mixer);
    if ((sampleIndex++ % 20) == 0) {
      samples.push_back(harness.lastDrySample(0));
      samples.push_back(harness.lastDrySample(1));
    }
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(-0.014590, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.014590, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.023030, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022458, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.034774, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.023873, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.082167, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.038823, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.016316, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004519, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.072060, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.007040, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.056595, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.003471, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.033718, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.007983, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004398, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.001822, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.017997, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.011382, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.021290, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.019311, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.030234, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.038725, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.018208, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.033121, samples[25], self.epsilon);
  XCTAssertEqualWithAccuracy(0.013147, samples[26], self.epsilon);
  XCTAssertEqualWithAccuracy(0.036698, samples[27], self.epsilon);
  XCTAssertEqualWithAccuracy(0.006571, samples[28], self.epsilon);
  XCTAssertEqualWithAccuracy(0.038005, samples[29], self.epsilon);
  XCTAssertEqualWithAccuracy(0.001577, samples[30], self.epsilon);
  XCTAssertEqualWithAccuracy(0.043627, samples[31], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.006705, samples[32], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.033710, samples[33], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.026536, samples[34], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.068912, samples[35], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.022025, samples[36], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.037783, samples[37], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.027964, samples[38], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.033267, samples[39], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineMIDIReset {
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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

  XCTAssertEqualWithAccuracy(0.003008, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.003023, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.002096, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.002096, samples[3], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineActiveVoiceCount
{
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto sampleIndex = 0;
  for (auto step = 1_F; step <= steps; ++step) {
    harness.setParameter(Index::pan, AUValue(step / steps * -500_F));
    harness.renderMaxFramesCount(mixer);
    if ((sampleIndex++ % 20) == 0) {
      samples.push_back(harness.lastDrySample(0));
      samples.push_back(harness.lastDrySample(1));
    }
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    harness.setParameter(Index::pan, AUValue(step / steps * -500_F));
    harness.renderMaxFramesCount(mixer);
    if ((sampleIndex++ % 20) == 0) {
      samples.push_back(harness.lastDrySample(0));
      samples.push_back(harness.lastDrySample(1));
    }
  }

  // Pan right
  for (auto step = 1_F; step <= steps; ++step) {
    harness.setParameter(Index::pan, AUValue(step / steps * 500_F));
    harness.renderMaxFramesCount(mixer);
    if ((sampleIndex++ % 20) == 0) {
      samples.push_back(harness.lastDrySample(0));
      samples.push_back(harness.lastDrySample(1));
    }
  }

  // Pan back to center
  for (auto step = steps - 1_F; step >= 0_F; --step) {
    harness.setParameter(Index::pan, AUValue(step / steps * 500_F));
    harness.renderMaxFramesCount(mixer);
    if ((sampleIndex++ % 20) == 0) {
      samples.push_back(harness.lastDrySample(0));
      samples.push_back(harness.lastDrySample(1));
    }
  }

  harness.renderToEnd(mixer);

  [self dumpSamples: samples];
  auto epsilon = self.epsilon;

  XCTAssertEqualWithAccuracy(-0.014590, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.014590, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022924, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.022567, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.034585, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.024145, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.082167, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.038823, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.016295, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004596, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.071991, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.007719, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.056572, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.003827, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.033706, samples[14], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.008036, samples[15], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004381, samples[16], self.epsilon);
  XCTAssertEqualWithAccuracy(0.001863, samples[17], self.epsilon);
  XCTAssertEqualWithAccuracy(0.017925, samples[18], self.epsilon);
  XCTAssertEqualWithAccuracy(0.011495, samples[19], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.021290, samples[20], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.019311, samples[21], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.030112, samples[22], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.038820, samples[23], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.017843, samples[24], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.033319, samples[25], self.epsilon);
  XCTAssertEqualWithAccuracy(0.012453, samples[26], self.epsilon);
  XCTAssertEqualWithAccuracy(0.036939, samples[27], self.epsilon);
  XCTAssertEqualWithAccuracy(0.006033, samples[28], self.epsilon);
  XCTAssertEqualWithAccuracy(0.038094, samples[29], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000754, samples[30], self.epsilon);
  XCTAssertEqualWithAccuracy(0.043649, samples[31], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.006281, samples[32], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.033792, samples[33], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.025450, samples[34], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.069320, samples[35], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.021728, samples[36], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.037954, samples[37], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.027544, samples[38], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.033616, samples[39], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.bufferFrameCount()];
}

- (void)testEngineChangePresetByIndex
{
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::allSoundOff, 0));
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineAllNotesOff
{
  auto harness{TestEngineHarness{}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::allNotesOff, 0));
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
}

- (void)testEngineResetAllControllers
{
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
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
  auto harness{TestEngineHarness{}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::omniOff, 0));
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}

- (void)testEngineOmniOn
{
  auto harness{TestEngineHarness{}};
  auto& engine{harness.engine()};
  harness.load(self.contexts->context0.path(), 0);

  harness.sendNoteOn(60);
  XCTAssertEqual(size_t(1), engine.activeVoiceCount());
  harness.sendRaw(engine.createChannelMessagePayload(MIDI::ControlChange::omniOn, 0));
  XCTAssertEqual(size_t(0), engine.activeVoiceCount());
}


- (void)testMIDIPitchBendDecodesFull14BitRange
{
  auto harness{TestEngineHarness{}};
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
    auto harness{TestEngineHarness{}};
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

- (void)testLiveAttenuationChangesAffectHeldNote
{
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibLiveAttenuation.sf2";
  SF2Builder::minimal().writeTo(path);

  auto reference = renderLiveAttenuationChange(path, [](TestEngineHarness&) {});
  auto verify = [&reference](const LiveAttenuationResult& result, double expected) {
    XCTAssertGreaterThan(result.before, 0.001);
    XCTAssertEqual(result.activeVoiceCount, size_t(1));
    XCTAssertEqualWithAccuracy(result.before / reference.before, 1.0, 0.001);
    XCTAssertEqualWithAccuracy(result.after / reference.after, expected, expected * 0.03);
  };

  // CC7 defaults to 100, so moving it to 64 adds 77 cB after lookup-table rounding.
  verify(renderLiveAttenuationChange(path, [](TestEngineHarness& harness) {
    harness.sendRaw(std::array<uint8_t, 3>{0xB0, 7, 64});
  }), std::pow(10.0, -77.0 / 200.0));

  // CC11 defaults to 127, so moving it to 64 adds the full 119.0495 cB from its default modulator.
  verify(renderLiveAttenuationChange(path, [](TestEngineHarness& harness) {
    harness.sendRaw(std::array<uint8_t, 3>{0xB0, 11, 64});
  }), std::pow(10.0, -119.049498788827904 / 200.0));

  auto parameterExpected = std::pow(10.0, -120.0 / 200.0);
  verify(renderLiveAttenuationChange(path, [](TestEngineHarness& harness) {
    harness.setParameter(Index::initialAttenuation, 120);
  }), parameterExpected);
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
  auto harness{TestEngineHarness{}};
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
  TestEngineHarness harness;
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

- (void)testMinimumNoteDurationCancelsShortNotes
{
  // A note released before it has played for the minimum note duration (default 10 ms) is cancelled with a fast
  // release instead of being played: a debounce for very short taps. The sine has a 2 s release, so a normal release
  // keeps the voice sounding while a cancelled note is gone within a few milliseconds. (The duration used to be passed
  // to `Voice::releaseKey` and ignored.)
  auto builder = SF2Builder::minimal();
  builder.igen.insert(builder.igen.begin(), {38, 1200});  // releaseVolEnv: 2 s
  builder.ibag[1].generatorIndex += 1;
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibMinimumNoteDuration.sf2";
  builder.writeTo(path);

  // Play key 69, release it after `heldFrames`, then render 10 ms more.
  struct Outcome { bool fastReleasing; size_t voicesAfter; };
  auto play = [&](AVAudioFrameCount heldFrames, size_t minimumMilliseconds, bool sustain) {
    auto harness{TestEngineHarness{48000.0}};
    XCTAssertEqual(harness.load(path, 0), SF2::IO::File::LoadResponse::ok);
    harness.engine().setMinimumNoteDuration(minimumMilliseconds);
    auto mixer{harness.createMixer(0.2)};
    if (sustain) harness.sendRaw(std::array<uint8_t, 3>{0xB0, 64, 127});
    harness.sendNoteOn(69, 127);
    harness.renderForCount(mixer, heldFrames);
    harness.sendNoteOff(69);
    bool fastReleasing = false;
    for (size_t index = 0; index < SF2::Render::Engine::traits::maxVoiceCount; ++index) {
      if (harness.voice(index).isActive() && harness.voice(index).isFastReleasing()) fastReleasing = true;
    }
    harness.renderForDuration(mixer, 0.010);
    return Outcome{fastReleasing, harness.engine().activeVoiceCount()};
  };

  XCTAssertEqual(SF2::Render::Engine::Engine().minimumNoteDuration(), size_t(10));

  // 5 ms tap with the default 10 ms minimum: cancelled.
  auto tap = play(240, 10, false);
  XCTAssertTrue(tap.fastReleasing);
  XCTAssertEqual(tap.voicesAfter, size_t(0));

  // 20 ms note: longer than the minimum, so it releases normally and is still sounding 10 ms later.
  auto held = play(960, 10, false);
  XCTAssertFalse(held.fastReleasing);
  XCTAssertEqual(held.voicesAfter, size_t(1));

  // A minimum of 0 turns the check off: the same 5 ms tap releases normally.
  auto disabled = play(240, 0, false);
  XCTAssertFalse(disabled.fastReleasing);
  XCTAssertEqual(disabled.voicesAfter, size_t(1));

  // A longer minimum cancels a longer note: 20 ms is under a 30 ms minimum.
  auto longer = play(960, 30, false);
  XCTAssertTrue(longer.fastReleasing);
  XCTAssertEqual(longer.voicesAfter, size_t(0));

  // The sustain pedal does not save a cancelled tap.
  auto sustained = play(240, 10, true);
  XCTAssertTrue(sustained.fastReleasing);
  XCTAssertEqual(sustained.voicesAfter, size_t(0));
}

@end
