// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

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

- (void)setUp {
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputRolandPiano {
  TestVoiceState voices{contexts.context2.makeVoiceState(0, 69, 127)};

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
  TestVoiceState voices{contexts.context0.makeVoiceState(205, 69, 127)};

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
        case 1: XCTAssertEqualWithAccuracy( 0.0468054898083, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy( 0.0371137671173, samples[index], epsilon); break;
      }
    }
  }
  else if constexpr (std::is_same_v<Float, double>) {
    for (auto index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy( 0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy( 0.0468283109367, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy( 0.0371137671173, samples[index], epsilon); break;
      }
    }
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testRolandPianoRender {
  // Play A Maj chord notes
  auto notes = contexts.context2.makeVoiceStates(0, {69, 73, 76}, 127);
  int seconds = 1;
  int sampleCount = notes.front().sampleRate() * seconds;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  // Each voice renders for 1/3 of a second
  size_t voiceSampleCount{size_t(sampleCount / 3)};
  // Release the key after 80% of the voice duration
  size_t keyReleaseCount{size_t(voiceSampleCount * 0.95)};

  std::vector<AUValue> samples;
  size_t start = 0;

  for (auto& voices : notes) {
    auto keyReleased = [self renderInto:buffer voices:voices forCount: keyReleaseCount startingAt: start];
    start += voiceSampleCount;
    samples.push_back([buffer left][start]);
    voices.releaseKey();
    auto end = [self renderInto:buffer voices:voices forCount: voiceSampleCount - keyReleaseCount startingAt: keyReleased];
    samples.push_back([buffer left][keyReleased]);
    samples.push_back([buffer left][end - 1]);
    voices.stop();
  }

  [self dumpSamples:samples];
  XCTAssertEqual(9, samples.size());

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
    XCTAssertEqualWithAccuracy( 0.0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy( 0.113844953477, samples[1], epsilon);
    XCTAssertEqualWithAccuracy( 0.147548079491, samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.0180835127831, samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 0.0844145715237, samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.0, samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 0.0206061471254, samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.0275252498686, samples[8], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testOrganRender {
  auto notes = contexts.context0.makeVoiceStates(40, {69, 73, 76}, 127);
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  size_t keyReleaseCount = sampleCount * 0.95;
  for (auto& note : notes) {
    auto keyReleased = [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];
    note.releaseKey();
    [self renderInto:buffer voices:note forCount:sampleCount - keyReleaseCount startingAt:keyReleaseCount];
  }

  [buffer normalize:notes.size()];

  auto samples = [buffer left];

  std::cout << std::setprecision(12);
  std::cout << 0 << ' ' << samples[0] << '\n';
  std::cout << 1 << ' ' << samples[keyReleaseCount] << '\n';
  std::cout << 2 << ' ' << samples[keyReleaseCount + 1] << '\n';
  std::cout << 3 << ' ' << samples[sampleCount - 1] << '\n';

  XCTAssertEqualWithAccuracy(0.0, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.192997559905, samples[keyReleaseCount], epsilon);
  XCTAssertEqualWithAccuracy(0.169460251927, samples[keyReleaseCount + 1], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[sampleCount - 1], epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRender {
  auto notes = contexts.context0.makeVoiceStates(80, {64, 68, 71}, 127);
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

    samples.push_back([buffer left][0]);
    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount afterRenderSample:^(size_t index) {
      int vibrato = int(100.0 * index / sampleCount);
      note[0].state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    }];

    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  std::cout << std::setprecision(12);
  for (auto index = 0; index < 9; ++index) {
    std::cout << index << ' ' << samples[index] << '\n';
  }

  XCTAssertEqual(9, samples.size());

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
    XCTAssertEqualWithAccuracy( 0.0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0223627388477, samples[1], epsilon);
    XCTAssertEqualWithAccuracy( 1.60971831065e-05, samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(-0.0464459881186, samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 5.33150523552e-05, samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.0, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(-0.174731999636, samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.000122439145343, samples[8], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithSlowAttack {
  // auto notes = contexts.context0.makeVoiceStates(80, {64, 68, 71}, 127);
  auto notes = contexts.context0.makeVoiceStates(80, {64}, 127);

  int seconds = 5;
  int sampleCount = notes.front().sampleRate() * seconds;
  int keyReleaseCount = sampleCount * 0.5;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  // Configure note to take 2.5s to attack and 2.5s to release
  for (auto& note : notes) {
    note.state().setValue(Voice::State::State::Index::attackVolumeEnvelope, 1586);
    note.state().setValue(Voice::State::State::Index::releaseVolumeEnvelope, 1586);
  }

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0];

    samples.push_back([buffer left][0]);
    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount];

    samples.push_back([buffer left][keyReleaseCount]);
    samples.push_back([buffer left][sampleCount - 1]);
  }

  std::cout << std::setprecision(12);
  for (auto index = 0; index < 9; ++index) {
    std::cout << index << ' ' << samples[index] << '\n';
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testLoopingModes {
  auto state = contexts.context2.makeVoiceState(0, 60, 32);
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
