// Copyright © 2020 Brad Howes. All rights reserved.

#include "SF2Lib/Types.hpp"

static SF2::Float epsilon = 1.0e-8;

#include <AVFoundation/AVFoundation.h>
#include <iostream>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.h"
#include "SF2Lib/Render/Preset.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

using namespace SF2;
using namespace SF2::Render;

@interface VoiceTests : SamplePlayingTestCase
@end

@implementation VoiceTests

- (void)testVoiceRepeatedRenderGeneratesSameOutputRolandPiano {
  TestVoiceCollection voices{contexts.context2.makeVoiceCollection(0, 69, 127)};

  int seconds = 10.0;
  int repetitions = 40.0;
  int sampleCount = voices.sampleRate() * seconds;

  AVAudioPCMBuffer* buffer = [self allocateBufferFor:voices capacity:sampleCount];
  size_t voiceSampleCount{size_t(sampleCount / repetitions)};
  size_t keyReleaseCount{size_t(voiceSampleCount * 0.99)};

  std::vector<AUValue> samples;

  for (auto iteration = 0; iteration < repetitions; ++iteration) {
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

  if constexpr (std::is_same_v<Float, float>) {
    for (auto index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy( 0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy( 0.132379963994, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy( -0.191177546978, samples[index], epsilon); break;
      }
    }
  }
  else if constexpr (std::is_same_v<Float, double>) {
    for (auto index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0:
          std::cout << std::setprecision(12);
          std::cout << index << ' ' << samples[index] << '\n';
          XCTAssertEqualWithAccuracy( 0.0000000000, samples[index], epsilon); break;
        case 1:
          std::cout << std::setprecision(12);
          std::cout << index << ' ' << samples[index] << '\n';
          XCTAssertEqualWithAccuracy(-0.184589236975, samples[index], epsilon); break;
        case 2:
          std::cout << std::setprecision(12);
          std::cout << index << ' ' << samples[index] << '\n';
          XCTAssertEqualWithAccuracy(-0.167654275894, samples[index], epsilon); break;
      }
    }
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputChimes {
  TestVoiceCollection voices{contexts.context0.makeVoiceCollection(205, 69, 127)};

  int seconds = 5;
  int repetitions = 5;
  int sampleCount = voices.sampleRate() * seconds;

  AVAudioPCMBuffer* buffer = [self allocateBufferFor:voices capacity:sampleCount];
  size_t voiceSampleCount{size_t(sampleCount / repetitions)};
  size_t keyReleaseCount{size_t(voiceSampleCount * 0.95)};

  std::vector<AUValue> samples;

  for (auto iteration = 0; iteration < repetitions; ++iteration) {
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

  if constexpr (std::is_same_v<Float, float>) {
    for (auto index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy( 0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy( 0.0478555746377, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy( 0.0369617044926, samples[index], epsilon); break;
      }
    }
  }
  else if constexpr (std::is_same_v<Float, double>) {
    for (auto index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy( 0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy( 0.0478555746377, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy( 0.0369617044926, samples[index], epsilon); break;
      }
    }
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testRolandPianoRender {
  auto notes = contexts.context2.makeVoicesCollection(0, {69, 73, 76}, 127);
  int seconds = 1;
  int sampleCount = notes.front().sampleRate() * seconds;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  size_t voiceSampleCount{size_t(sampleCount / 3)};
  size_t keyReleaseCount{size_t(voiceSampleCount * 0.95)};

  std::vector<AUValue> samples;
  size_t start = 0;

  for (auto& note : notes) {
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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy( 0.00000000000, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.19430789350, samples[1], epsilon);
    XCTAssertEqualWithAccuracy( 0.07492157817, samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.00000000000, samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.07910299301, samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 0.04325843975, samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.00000000000, samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 0.08214095235, samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.01485249959, samples[8], epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy( 0.0,               samples[0], epsilon);
    XCTAssertEqualWithAccuracy( 0.0975520834327,   samples[1], epsilon);
    XCTAssertEqualWithAccuracy( 0.113844953477,    samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.147548079491,    samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 0.0102697936818,   samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.0180835127831,   samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 0.0844145715237,   samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.000967499741819, samples[9], epsilon);
    XCTAssertEqualWithAccuracy( 0.0206061471254,   samples[10], epsilon);
    XCTAssertEqualWithAccuracy( 0.0275252498686,   samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testOrganRender {
  auto notes = contexts.context0.makeVoicesCollection(40, {69, 73, 76}, 127);
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  size_t keyReleaseCount = sampleCount * 0.95;

  for (auto& note : notes) {
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];
    note.releaseKey();
    [self renderInto:buffer voices:note forCount:sampleCount - keyReleaseCount startingAt:keyReleaseCount];
  }

  [buffer normalize:notes.size()];

  auto samples = [buffer left];

  std::cout << std::setprecision(12);
  std::cout << 0 << ' ' << samples[0] << '\n';
  std::cout << 1 << ' ' << samples[keyReleaseCount - 1] << '\n';
  std::cout << 2 << ' ' << samples[keyReleaseCount] << '\n';
  std::cout << 3 << ' ' << samples[sampleCount - 1] << '\n';

  XCTAssertEqualWithAccuracy(0.0, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.215462699533, samples[keyReleaseCount - 1], epsilon);
  XCTAssertEqualWithAccuracy(0.19288675487, samples[keyReleaseCount], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[sampleCount - 1], epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithVibrator {
  auto notes = contexts.context0.makeVoicesCollection(80, {64, 68, 71}, 127);
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  int keyReleaseCount = sampleCount * 0.95;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0 afterRenderSample:^(size_t index) {
      int vibrato = int(100.0 * index / sampleCount);
      note[0].state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    }];

    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount afterRenderSample:^(size_t index) {
      int vibrato = int(100.0 * index / sampleCount);
      note[0].state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    }];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount - 1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  XCTAssertEqual(4 * notes.size(), samples.size());

  std::cout << std::setprecision(12);
  for (auto index = 0; index < samples.size(); ++index) {
    std::cout << index << ' ' << samples[index] << '\n';
  }

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy( 0.00000000000, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.19430789350, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.19430789350, samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.07492157817, samples[3], epsilon);

    XCTAssertEqualWithAccuracy( 0.00000000000, samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 0.07910299301, samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.07910299301, samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 0.04325843975, samples[7], epsilon);

    XCTAssertEqualWithAccuracy( 0.00000000000, samples[8], epsilon);
    XCTAssertEqualWithAccuracy( 0.08214095235, samples[9], epsilon);
    XCTAssertEqualWithAccuracy( 0.08214095235, samples[10], epsilon);
    XCTAssertEqualWithAccuracy( 0.01485249959, samples[11], epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy( 0.0,               samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0148879569024,   samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0250362474471,   samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 1.62226642715e-05, samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0298092532903,   samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.0525057427585,   samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 5.49942305952e-05, samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.163673266768,    samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.175615653396,    samples[10], epsilon);
    XCTAssertEqualWithAccuracy( 0.000123127101688, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithSlowAttack {
  auto notes = contexts.context0.makeVoicesCollection(80, {64, 68, 71}, 127);
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  int keyReleaseCount = sampleCount * 0.95;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  // Configure note to take 2.5s to attack and 2.5s to release
  for (auto& note : notes) {
    for (auto voiceIndex = 0; voiceIndex < note.count(); ++voiceIndex) {
      note[voiceIndex].state().setValue(Voice::State::State::Index::attackVolumeEnvelope, 1586);
      note[voiceIndex].state().setValue(Voice::State::State::Index::releaseVolumeEnvelope, 1586);
    }
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

  std::cout << std::setprecision(12);
  for (auto index = 0; index < samples.size(); ++index) {
    std::cout << index << ' ' << samples[index] << '\n';
  }

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy( 0.00000000000, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.19430789350, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.19430789350, samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.07492157817, samples[3], epsilon);

    XCTAssertEqualWithAccuracy( 0.00000000000, samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 0.07910299301, samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.07910299301, samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 0.04325843975, samples[7], epsilon);

    XCTAssertEqualWithAccuracy( 0.00000000000, samples[8], epsilon);
    XCTAssertEqualWithAccuracy( 0.08214095235, samples[9], epsilon);
    XCTAssertEqualWithAccuracy( 0.08214095235, samples[10], epsilon);
    XCTAssertEqualWithAccuracy( 0.01485249959, samples[11], epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy( 0.0,               samples[0], epsilon);
    XCTAssertEqualWithAccuracy( 0.0156193356961,   samples[1], epsilon);
    XCTAssertEqualWithAccuracy( 0.0104945795611,   samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-1.52093052748e-05, samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 0.0702599808574,   samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.0530981980264,   samples[6], epsilon);
    XCTAssertEqualWithAccuracy(-3.52471070073e-05, samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[8], epsilon);
    XCTAssertEqualWithAccuracy( 0.0527060478926,   samples[9], epsilon);
    XCTAssertEqualWithAccuracy( 0.0403794385493,   samples[10], epsilon);
    XCTAssertEqualWithAccuracy(-4.20717369707e-05, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testLoopingModes {
  auto state = contexts.context2.makeVoiceCollection(0, 60, 32);
  auto& voice = state[0];

  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  voice.state().setValue(Voice::State::State::Index::sampleModes, -1);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  voice.state().setValue(Voice::State::State::Index::sampleModes, 1);
  XCTAssertEqual(Voice::Voice::LoopingMode::activeEnvelope, voice.loopingMode());
  voice.state().setValue(Voice::State::State::Index::sampleModes, 2);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  voice.state().setValue(Voice::State::State::Index::sampleModes, 3);
  XCTAssertEqual(Voice::Voice::LoopingMode::duringKeyPress, voice.loopingMode());
  voice.state().setValue(Voice::State::State::Index::sampleModes, 4);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
}

@end
