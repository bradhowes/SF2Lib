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
  auto harness{TestEngineHarness{48000.0}};
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

  XCTAssertEqualWithAccuracy(0.041004, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.008083, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.010874, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.020511, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004914, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.022331, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004624, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.022621, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004223, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.022907, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004101, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.022944, samples[11], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004102, samples[12], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.022932, samples[13], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000005, samples[14], self.epsilon);

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
      case 1: XCTAssertEqualWithAccuracy(-0.010416, samples[index], self.epsilon); break;
      case 2: XCTAssertEqualWithAccuracy(-0.001273, samples[index], self.epsilon); break;
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
  XCTAssertEqualWithAccuracy(-0.023803, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.021572, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.019941, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.023081, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.021693, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.003675, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.001589, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.001031, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.003087, samples[11], self.epsilon);

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
  XCTAssertEqualWithAccuracy(0.001026, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.001011, samples[2], self.epsilon);
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
  XCTAssertEqualWithAccuracy(0.001024, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.001010, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004289, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.004316, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.008494, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.008456, samples[10], self.epsilon);
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
  XCTAssertEqualWithAccuracy(0.011859, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.009909, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.036409, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.033301, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.033357, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.029278, samples[10], self.epsilon);
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
  XCTAssertEqualWithAccuracy(-0.010138, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.009330, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.008464, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.002201, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.019225, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.019397, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.019662, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000481, samples[9], self.epsilon);

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
  XCTAssertEqualWithAccuracy(0.019133, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.020261, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000020, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(0.027418, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(0.028742, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000047, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(0.034174, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(0.034216, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000013, samples[11], self.epsilon);

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
  XCTAssertEqualWithAccuracy(-0.006852, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.008199, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.000829, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.002664, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.005563, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.006361, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.012454, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.013056, samples[10], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.012638, samples[11], self.epsilon);

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
  XCTAssertEqualWithAccuracy(0, samples[0], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.005949, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.006342, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[3], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[4], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.010493, samples[5], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.008408, samples[6], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[7], self.epsilon);
  XCTAssertEqualWithAccuracy(0, samples[8], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.008480, samples[9], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.003351, samples[10], self.epsilon);
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
  XCTAssertEqualWithAccuracy(-0.048441, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(-0.048249, samples[2], self.epsilon);
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
  XCTAssertEqualWithAccuracy(0.022372, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.018646, samples[2], self.epsilon);
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
  XCTAssertEqualWithAccuracy(0.014029, samples[1], self.epsilon);
  XCTAssertEqualWithAccuracy(0.014878, samples[2], self.epsilon);
  XCTAssertEqualWithAccuracy(0.000015, samples[3], self.epsilon);

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
