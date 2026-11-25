// Copyright © 2020, 2025 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>

#include <iomanip>
#include <iostream>

#include "SampleBasedContexts.hpp"

#include "SF2Util/Types.hpp"
#include "SF2Lib/Configuration.hpp"
#include "SF2Lib/Render/Preset.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Voice::State;

@interface VoiceTests : SamplePlayingTestCase
@end

@implementation VoiceTests

- (void)setUp {
  [super setUp];
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputRolandPiano {
  auto harness{TestEngineHarness{48000.0, 96}};
  harness.load(self.contexts->context2.path(), 0);

  double seconds = 4.0;
  int repetitions = 14;
  auto mixer{harness.createMixer(seconds)};

  auto playing = seconds / 2;
  auto noteDuration = playing / repetitions;

  std::vector<AUValue> samples;
  uint8_t note = 64;
  for (auto iteration = 1; iteration <= repetitions; ++iteration) {
    harness.sendNoteOn(note);
    harness.renderForDuration(mixer, noteDuration);
    samples.push_back(harness.lastDrySample());
    harness.sendNoteOff(note);
    note = note == 64 ? 65 : 64;
  }

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  std::cout << std::setprecision(12);

  XCTAssertEqualWithAccuracy(0.0536821633577, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0147259831429, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0305624380708, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0242499131709, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0266245156527, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0241541340947, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0269547197968, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0243006944656, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0267410967499, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0243631061167, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0267161950469, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0243697613478, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0267082154751, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0243727508932, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(9.68133463175e-07, samples[14], self.epsilon);

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputChimes {
  TestVoiceCollection voices{self.contexts->context0.makeVoiceCollection(163, 69)};

  int seconds = 5;
  AVAudioFrameCount repetitions = 5;
  auto sampleCount = AVAudioFrameCount(voices.sampleRate() * seconds);

  AVAudioPCMBuffer* buffer = [self allocateBufferFor:voices capacity:sampleCount];
  auto voiceSampleCount{AVAudioFrameCount(sampleCount / repetitions)};
  auto keyReleaseCount{AVAudioFrameCount(voiceSampleCount * 0.95)};

  std::vector<AUValue> samples;

  for (AVAudioFrameCount iteration = 0; iteration < repetitions; ++iteration) {
    voices.start();
    auto start = iteration * voiceSampleCount;
    auto keyReleased = [self renderInto:buffer voices:voices forCount: keyReleaseCount startingAt: start];
    samples.push_back([buffer left][start]);
    voices.releaseKey();
    auto end = [self renderInto:buffer voices:voices forCount: voiceSampleCount - keyReleaseCount startingAt: keyReleased];
    samples.push_back([buffer left][keyReleased]);
    samples.push_back([buffer left][end - 1]);
    voices.stop();
  }

  [self dumpSamples: samples];

  XCTAssertEqual(repetitions * 3, samples.size());

  for (size_t index = 0; index < samples.size(); ++index) {
    switch (index % 3) {
      case 0: XCTAssertEqualWithAccuracy(0.0000000000, samples[index], self.epsilon); break;
      case 1: XCTAssertEqualWithAccuracy(0.0200641788542, samples[index], self.epsilon); break;
      case 2: XCTAssertEqualWithAccuracy(-0.00118414440658, samples[index], self.epsilon); break;
    }
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testRolandPianoRender {
  auto notes = self.contexts->context2.makeVoicesCollection(0, {69, 73, 76});
  int seconds = 1;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  AVAudioFrameCount voiceSampleCount{AVAudioFrameCount(sampleCount / 3)};
  AVAudioFrameCount keyReleaseCount{AVAudioFrameCount(voiceSampleCount * 0.95)};

  std::vector<AUValue> samples;
  size_t start = 0;

  for (auto& note : notes) {
    note.start();
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: start];
    note.releaseKey();
    [self renderInto:buffer voices:note forCount: voiceSampleCount - keyReleaseCount
          startingAt: start + keyReleaseCount];

    samples.push_back([buffer left][start]);
    samples.push_back([buffer left][start + keyReleaseCount - 1]);
    samples.push_back([buffer left][start + keyReleaseCount]);
    samples.push_back([buffer left][start + voiceSampleCount - 1]);

    start += voiceSampleCount;
  }

  [self dumpSamples:samples];

  XCTAssertEqual(4 * notes.size(), samples.size());

  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00919648539275, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.006830858998, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0220509432256, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0139260478318, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0123555259779, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00820960849524, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00204696785659, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00279987393878, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000521605135873, samples[11], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testRolandReleaseDuration {
  auto notes = self.contexts->context0.makeVoicesCollection(0, {69});
  int seconds = 10;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  AVAudioFrameCount voiceSampleCount = sampleCount;
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(voiceSampleCount * 0.05);

  std::vector<AUValue> samples;
  size_t start = 0;

  for (auto& note : notes) {
    note.start();
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: start];
    note.releaseKey();
    [self renderInto:buffer voices:note forCount: voiceSampleCount - keyReleaseCount
          startingAt: start + keyReleaseCount];

    samples.push_back([buffer left][start]);
    samples.push_back([buffer left][start + keyReleaseCount - 1]);
    samples.push_back([buffer left][start + keyReleaseCount]);
    samples.push_back([buffer left][start + voiceSampleCount - 1]);

    start += voiceSampleCount;
  }

  [self dumpSamples:samples];

  XCTAssertEqual(4 * notes.size(), samples.size());

  XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000208982557524, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00050186336739, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testYamahaRender {
  auto notes = self.contexts->context0.makeVoicesCollection(0, {69, 73, 76});
  int seconds = 3;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.3);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    note.start();

    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];

    note.releaseKey();

    [self renderInto:buffer voices:note forCount:sampleCount - keyReleaseCount startingAt:keyReleaseCount];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount - 1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  // [buffer normalize:notes.size()];
  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00196727947332, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00215472490527, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00111728045158, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00134610873647, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000542938476428, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00095455092378, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[11], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testOrganRender {
  auto notes = self.contexts->context0.makeVoicesCollection(18, {69, 73, 76});
  int seconds = 2;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.95);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    note.start();

    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];

    note.releaseKey();

    [self renderInto:buffer voices:note forCount:sampleCount - keyReleaseCount startingAt:keyReleaseCount];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount - 1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  // [buffer normalize:notes.size()];
  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];

  auto epsilon = self.epsilon;

  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0343283042312, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0344554111362, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.038421984762, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0376352146268, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0338357724249, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0336385257542, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[11], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testCelloRenderOneNote {
  auto notes = self.contexts->context0.makeVoicesCollection(42, {48, 55});
  auto seconds = 1.5;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.95);
  AVAudioPCMBuffer* buffer = [self allocateBuffer:notes.front().sampleRate() numberOfChannels:1 capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    note.start();
    [self renderInto:buffer mono:note[0] forCount:keyReleaseCount startingAt:0];

    note.releaseKey();

    [self renderInto:buffer mono:note[0] forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount - 1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][keyReleaseCount + 1]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00389041844755, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00436023203656, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00480151874945, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000306368427118, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0021377983503, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00280895922333, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00363417016342, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00218217424117, samples[9], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderChord {
  auto notes = self.contexts->context0.makeVoicesCollection(49, {76, 79, 83});
  auto seconds = 2.0;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.5);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    note.start();
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];

    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount - 1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0107690254226, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0114954309538, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-4.47510410595e-06, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00162554252893, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00441766250879, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000114834445412, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0012203452643, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00667950324714, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000122817480587, samples[11], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithVibrato {
  auto notes = self.contexts->context0.makeVoicesCollection(49, {76, 79, 83});
  int seconds = 3;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.95);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    note.start();
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0 afterRenderSample:^(size_t index) {
      int vibrato = int(100.0 * Float(index) / sampleCount);
      self.sst.setValue(note[0].state(), Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    }];

    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount afterRenderSample:^(size_t index) {
      int vibrato = int(100.0 * Float(index) / sampleCount);
      self.sst.setValue(note[0].state(), Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    }];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount - 1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0170871168375, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0147927841172, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00194881658535, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.015974868089, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00933495908976, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00610914779827, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0270554218441, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0188599284738, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00841659680009, samples[11], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithSlowAttackRelease {
  auto notes = self.contexts->context0.makeVoicesCollection(40, {64, 68, 71});
  int seconds = 3;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.5);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  // Configure note to take 1.5s to attack and release
  for (auto& note : notes) {
    for (size_t voiceIndex = 0; voiceIndex < note.count(); ++voiceIndex) {
      self.sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::attackVolumeEnvelope, int(::DSP::secondsToCents(1.5)));
      self.sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::releaseVolumeEnvelope, int(::DSP::secondsToCents(1.5)));
      self.sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::sampleModes, 1);
    }
    note.start();
  }

  std::vector<AUValue> samples;

  for (auto& note : notes) {
    note.start();

    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];

    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount-1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];
  auto epsilon = self.epsilon;

  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00442309165373, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00526761543006, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00362962344661, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00399142224342, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000959726748988, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00180648546666, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[11], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testSlowAttackRelease {
  auto notes = self.contexts->context0.makeVoicesCollection(197, {64});
  int seconds = 4;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(notes.front().sampleRate() * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.5);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;

  for (auto& note : notes) {

    for (size_t voiceIndex = 0; voiceIndex < note.count(); ++voiceIndex) {
      // Configure volume envelope for 2s attack.
      self.sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::attackVolumeEnvelope, 1200);
      self.sst.setAdjustment(note[voiceIndex].state(), Voice::State::State::Index::attackVolumeEnvelope, 0);
      // Configure volume envelope for 2s release.
      self.sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::releaseVolumeEnvelope, 1200);
      self.sst.setAdjustment(note[voiceIndex].state(), Voice::State::State::Index::releaseVolumeEnvelope, 0);
      // Configure sample generator to loop until volume envelope is done.
      self.sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::sampleModes, 1);
      note[voiceIndex].start();
    }
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];
    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount-1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.00835953373462, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0103789567947, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testCelesta {
  auto notes = self.contexts->context0.makeVoicesCollection(11, {64}, 127);
  auto sampleRate = notes.front().sampleRate();
  int seconds = 2;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(sampleRate * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.25);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    note.start();
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];
    note.releaseKey();
    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount];
    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount-1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
    note.stop();
  }

  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0168364364654, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0188367124647, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testHarp {
  auto notes = self.contexts->context0.makeVoicesCollection(46, {76});
  auto sampleRate = notes.front().sampleRate();
  int seconds = 3;
  AVAudioFrameCount sampleCount = AVAudioFrameCount(sampleRate * seconds);
  AVAudioFrameCount keyReleaseCount = AVAudioFrameCount(sampleCount * 0.5);
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    note.start();
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];
    note.releaseKey();
    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount];
    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount-1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
    note.stop();
  }

  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];

  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00337297166698, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.00497201085091, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-3.23682579619e-05, samples[3], self.epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testLoopingModes {
  auto state = self.contexts->context2.makeVoiceCollection(0, 60);
  auto& voice = state[0];

  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  self.sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, -1);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  self.sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, 1);
  XCTAssertEqual(Voice::Voice::LoopingMode::activeEnvelope, voice.loopingMode());
  self.sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, 2);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  self.sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, 3);
  XCTAssertEqual(Voice::Voice::LoopingMode::duringKeyPress, voice.loopingMode());
  self.sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, 4);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
}

- (void)testSostenuto {
  auto state = self.contexts->context0.makeVoiceCollection(0, 60);
  auto& voice = state[0];
  voice.start();
  while (voice.renderSample() == 0.0) ;
  XCTAssertTrue(voice.isKeyDown());
  voice.useSostenuto();
  XCTAssertTrue(voice.isKeyDown());
  voice.renderSample();

  // Key up while sostenuto holds the voice: release is postponed.
  voice.releaseKey({1, {false, true, false}});
  voice.renderSample();
  XCTAssertFalse(voice.isKeyDown());
  XCTAssertTrue(voice.isReleasePostponed());
  XCTAssertFalse(voice.isReleased());

  // Sustain going up while sostenuto is still down does not release the voice.
  voice.pedalReleased({false, true, false});
  voice.renderSample();
  XCTAssertTrue(voice.isReleasePostponed());
  XCTAssertFalse(voice.isReleased());

  // Sostenuto going up releases it.
  voice.pedalReleased({false, false, false});
  voice.renderSample();
  XCTAssertFalse(voice.isReleasePostponed());
  XCTAssertTrue(voice.isReleased());
}

- (void)testSostenutoDoesNotHoldVoiceThatWasNotCaptured {
  auto state = self.contexts->context0.makeVoiceCollection(0, 60);
  auto& voice = state[0];
  voice.start();
  while (voice.renderSample() == 0.0) ;

  // Sostenuto is down but this voice was not held when it went down, so key up releases it straight away.
  voice.releaseKey({1, {false, true, false}});
  XCTAssertFalse(voice.isReleasePostponed());
  XCTAssertTrue(voice.isReleased());
}

- (void)testSustain {
  auto state = self.contexts->context0.makeVoiceCollection(0, 60);
  auto& voice = state[0];
  voice.start();
  XCTAssertTrue(voice.isKeyDown());
  while (voice.renderSample() == 0.0) ;

  voice.releaseKey({1, {true, false, false}});
  voice.renderSample();
  XCTAssertFalse(voice.isKeyDown());
  XCTAssertTrue(voice.isReleasePostponed());
  XCTAssertFalse(voice.isReleased());

  // Sostenuto going up while sustain is still down does not release the voice.
  voice.pedalReleased({true, false, false});
  voice.renderSample();
  XCTAssertTrue(voice.isReleasePostponed());
  XCTAssertFalse(voice.isReleased());

  voice.pedalReleased({false, false, false});
  voice.renderSample();
  XCTAssertFalse(voice.isReleasePostponed());
  XCTAssertTrue(voice.isReleased());
}

- (void)testPedalReleaseDoesNotReleaseHeldKey {
  auto state = self.contexts->context0.makeVoiceCollection(0, 60);
  auto& voice = state[0];
  voice.start();
  while (voice.renderSample() == 0.0) ;

  // Sustain (and sostenuto) went down and came back up while the key stayed down.
  voice.useSostenuto();
  voice.pedalReleased({false, false, false});
  voice.renderSample();
  XCTAssertTrue(voice.isKeyDown());
  XCTAssertFalse(voice.isReleasePostponed());
  XCTAssertFalse(voice.isReleased());

  // The real note-off still releases it.
  voice.releaseKey({1, {false, false, false}});
  XCTAssertFalse(voice.isKeyDown());
  XCTAssertTrue(voice.isReleased());
}

- (void)testSostenutoIsForgottenWhenPedalLifts {
  auto state = self.contexts->context0.makeVoiceCollection(0, 60);
  auto& voice = state[0];
  voice.start();
  while (voice.renderSample() == 0.0) ;

  // Captured by sostenuto, which then lifts while the key is still down.
  voice.useSostenuto();
  voice.pedalReleased({false, false, false});

  // A later sostenuto press that did not capture this voice must not hold it.
  voice.releaseKey({1, {false, true, false}});
  XCTAssertFalse(voice.isReleasePostponed());
  XCTAssertTrue(voice.isReleased());
}

- (void)testStartClearsPedalState {
  auto state = self.contexts->context0.makeVoiceCollection(0, 60);
  auto& voice = state[0];
  voice.start();
  while (voice.renderSample() == 0.0) ;
  voice.useSostenuto();
  voice.releaseKey({1, {true, true, false}});
  XCTAssertTrue(voice.isReleasePostponed());

  // Recycle the voice for a new note. It must not inherit sostenuto or the postponed release from the last one.
  voice.start();
  XCTAssertTrue(voice.isKeyDown());
  XCTAssertFalse(voice.isReleasePostponed());
  XCTAssertFalse(voice.isReleased());
  while (voice.renderSample() == 0.0) ;

  voice.releaseKey({1, {false, true, false}});
  XCTAssertFalse(voice.isReleasePostponed());
  XCTAssertTrue(voice.isReleased());
}

@end
