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
        case 0: XCTAssertEqualWithAccuracy(0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy(-0.20165361464, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy(-0.271317273378, samples[index], epsilon); break;
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
          XCTAssertEqualWithAccuracy(-0.201649993658, samples[index], epsilon); break;
        case 2:
          std::cout << std::setprecision(12);
          std::cout << index << ' ' << samples[index] << '\n';
          XCTAssertEqualWithAccuracy(-0.274465858936, samples[index], epsilon); break;
      }
    }
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputChimes {
  TestVoiceCollection voices{contexts.context0.makeVoiceCollection(163, 69, 127)};

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
        case 0: XCTAssertEqualWithAccuracy(0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy(0.0111224222928, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy(0.00317874527536, samples[index], epsilon); break;
      }
    }
  }
  else if constexpr (std::is_same_v<Float, double>) {
    for (auto index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy(0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy(0.0109653398395, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy(0.00356790143996, samples[index], epsilon); break;
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
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.128517314792, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.107323430479, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.11131759733, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(0.0638395249844, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(0.0724022015929, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0.137387365103, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(0.116560056806, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(0.120563536882, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0.123455472291, samples[11], epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.128510698676, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.107315845788, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.11260997504, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(0.0638429820538, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(0.0724058225751, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0.138983160257, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(0.116553209722, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(0.120560325682, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0.124852158129, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testOrganRender {
  auto notes = contexts.context0.makeVoicesCollection(18, {69, 73, 76}, 127);
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.95;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.114197462797, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.113293237984, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.148109078407, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.140772968531, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(0.0182730704546, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(0.0210941880941, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[11], epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy( 0.0,               samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0138919819146, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0137808090076, samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0180372502655, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.0171416886151, samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[8], epsilon);
    XCTAssertEqualWithAccuracy(0.00221552886069, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(0.00255012582056, samples[10], epsilon);
    XCTAssertEqualWithAccuracy( 0.0,               samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRender1 {
  auto notes = contexts.context0.makeVoicesCollection(40, {64}, 127);
  int seconds = 1;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.95;
  AVAudioPCMBuffer* buffer = [self allocateBuffer:notes.front().sampleRate() numberOfChannels:1 capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.00364254624583, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.00210017827339, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.0023496679496, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(-0.00281907012686, samples[4], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.00320144742727, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.00187076092698, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.00219892919995, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(-0.00790938641876, samples[4], epsilon);
  }
  [self playSamples: buffer count: sampleCount];
  buffer = nil;
}

- (void)testViolinRender {
  auto notes = contexts.context0.makeVoicesCollection(40, {64, 68, 71}, 127);
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.95;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0793079808354, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0705065429211, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(1.06012303149e-05, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.00973602384329, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00511918962002, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(1.91168401216e-05, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.040793273598, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0392105169594, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(9.74768136075e-06, samples[11], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0534844398499, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0473236255348, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.000243789734668, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0065136407502, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00325362035073, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0.000439928699052, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.0276693683118, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0263410378247, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0.000222541799303, samples[11], epsilon);
  }
  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithVibrato {
  auto notes = contexts.context0.makeVoicesCollection(40, {64, 68, 71}, 127);
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.95;
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

  [self dumpSamples: samples];

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.0559814758599, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.052519839257, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(3.17845551763e-05, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(0.112895518541, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(0.0982752144337, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(6.28374400549e-05, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.0129413604736, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0301705002785, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0.000106911902549, samples[11], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.0383135303855, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.0356729328632, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.000726376078092, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(0.0776512399316, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(0.0676524415612, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0.00144103763159, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.00710120797157, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0189772415906, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0.00244267843664, samples[11], epsilon);
  }
  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithSlowAttack {
  auto notes = contexts.context0.makeVoicesCollection(40, {64, 68, 71}, 127);
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

  [self dumpSamples: samples];

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0793079808354, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0705065429211, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(1.06012303149e-05, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.00973602384329, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00511918962002, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(1.91168401216e-05, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.040793273598, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0392105169594, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(9.74768136075e-06, samples[11], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0534844398499, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0473236255348, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.000243789734668, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0065136407502, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00325362035073, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0.000439928699052, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.0276693683118, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0263410378247, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0.000222541799303, samples[11], epsilon);
  }
  [self playSamples: buffer count: sampleCount];
}

- (void)testSlowAttackDecay {
  auto notes = contexts.context0.makeVoicesCollection(197, {64}, 127);
  int seconds = 4;
  int sampleCount = notes.front().sampleRate() * seconds;
  int keyReleaseCount = sampleCount * 0.5;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  // Configure note to take 1s to attack and 1s to release
  for (auto& note : notes) {
    for (auto voiceIndex = 0; voiceIndex < note.count(); ++voiceIndex) {
      note[voiceIndex].state().setValue(Voice::State::State::Index::attackVolumeEnvelope, 1200);
      note[voiceIndex].state().setAdjustment(Voice::State::State::Index::releaseVolumeEnvelope, 0);
      note[voiceIndex].state().setValue(Voice::State::State::Index::attackVolumeEnvelope, 1200);
      note[voiceIndex].state().setAdjustment(Voice::State::State::Index::releaseVolumeEnvelope, 0);
    }
  }

  std::vector<AUValue> samples;

  for (auto& note : notes) {
    note.start();
    std::cout << "- start\n";
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];

    std::cout << "- release\n";
    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount];

    samples.push_back([buffer left][0]);
    samples.push_back([buffer left][keyReleaseCount-1]);
    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  XCTAssertEqual(4 * notes.size(), samples.size());

  [self dumpSamples: samples];

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0715493783355, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0556658469141, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.0626768916845, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.0729342401028, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
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
