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
  auto harness{TestEngineHarness{48000.0, 96, SF2::Render::Voice::Sample::Interpolator::cubic4thOrder}};
  harness.load(self.contexts->context2.path(), 0);

  int seconds = 4;
  int repetitions = 14;
  auto mixer{harness.createMixer(seconds)};

  auto renderCount = harness.renders();
  auto playing = renderCount / 2;

  auto noteOnRenders = playing / AVAudioFrameCount(repetitions);
  auto runningRenders = AVAudioFrameCount{0};

  std::vector<AUValue> samples;

  uint8_t note = 64;
  for (auto iteration = 1; iteration <= repetitions; ++iteration) {
    harness.sendNoteOn(note);
    runningRenders += noteOnRenders;
    harness.renderUntil(mixer, runningRenders);
    samples.push_back(harness.lastDrySample());
    harness.sendNoteOff(note);
    note = note == 64 ? 65 : 64;
  }

  harness.renderToEnd(mixer);
  samples.push_back(harness.lastDrySample());

  [self dumpSamples: samples];

  std::cout << std::setprecision(12);

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(-0.0684094578028, samples[0], self.epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(-0.0698643401265, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00836191140115, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0588994584978, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00935971178114, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0550728663802, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0126139139757, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0547123402357, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0134199066088, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0541706979275, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0136071350425, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0541077405214, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0136712500826, samples[11], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0540701821446, samples[12], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0136786820367, samples[13], self.epsilon);
    XCTAssertEqualWithAccuracy(1.30052876557e-06, samples[14], self.epsilon);
  }

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

  if constexpr (std::is_same_v<Float, float>) {
    for (size_t index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy(0.0000000000, samples[index], self.epsilon); break;
        case 1: XCTAssertEqualWithAccuracy(0.0111224222928, samples[index], self.epsilon); break;
        case 2: XCTAssertEqualWithAccuracy(0.00317874527536, samples[index], self.epsilon); break;
      }
    }
  }
  else if constexpr (std::is_same_v<Float, double>) {
    for (size_t index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy(0.0000000000, samples[index], self.epsilon); break;
        case 1: XCTAssertEqualWithAccuracy(0.0168082546443, samples[index], self.epsilon); break;
        case 2: XCTAssertEqualWithAccuracy(-0.00124768540263, samples[index], self.epsilon); break;
      }
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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(0.128517314792, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(0.107323430479, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.11131759733, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0638395249844, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0724022015929, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(0.137387365103, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(0.116560056806, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(0.120563536882, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(0.123455472291, samples[11], self.epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00919859670103, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00683849584311, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.02204583399, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0139200314879, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0123502006754, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(0.00821241363883, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(0.00203400268219, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(0.00278515834361, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(0.000516511325259, samples[11], self.epsilon);
  }

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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(0.128517314792, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(0.107323430479, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.11131759733, samples[3], self.epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.000220100017032, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.000506518699694, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
  }

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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.114197462797, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.113293237984, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.148109078407, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.140772968531, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0182730704546, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0210941880941, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[11], self.epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00195370847359, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00213433802128, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00109550275374, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00132327864412, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00053169374587, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.000934656127356, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[11], self.epsilon);
  }

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
  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.114197462797, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.113293237984, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.148109078407, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.140772968531, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0182730704546, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0210941880941, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[11], self.epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0342836864293, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0344120599329, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0391573309898, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.0380108244717, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.0340084172785, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0331242568791, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[11], epsilon);
  }

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
  auto epsilon = self.epsilon;

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(0.00364254624583, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(0.00210017827339, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0023496679496, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00281907012686, samples[4], self.epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00390073889866, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00436056032777, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-0.00479530915618, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0.000310773029923, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00216313637793, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(-0.00283227767795, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(-0.00359885301441, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(0.00217619538307, samples[9], epsilon);
  }

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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0793079808354, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0705065429211, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(1.06012303149e-05, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00973602384329, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00511918962002, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(1.91168401216e-05, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.040793273598, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0392105169594, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(9.74768136075e-06, samples[11], self.epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0109371868894, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0117771374062, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(-2.88044907393e-06, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(0.000967659056187, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0049067963846, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(0.000114318187116, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00204970920458, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0072527024895, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(0.000121989636682, samples[11], self.epsilon);
  }

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
  auto epsilon = self.epsilon;

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0559814758599, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(0.052519839257, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(3.17845551763e-05, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(0.112895518541, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0982752144337, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(6.28374400549e-05, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0129413604736, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0301705002785, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(0.000106911902549, samples[11], self.epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.017094168812, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0152829913422, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-0.00196327478625, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0165916401893, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.0104964738712, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(-0.00620357505977, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.0277099013329, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0204559918493, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(-0.00847473740578, samples[11], epsilon);
  }

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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0793079808354, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0705065429211, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(1.06012303149e-05, samples[3], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[4], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00973602384329, samples[5], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00511918962002, samples[6], self.epsilon);
    XCTAssertEqualWithAccuracy(1.91168401216e-05, samples[7], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[8], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.040793273598, samples[9], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0392105169594, samples[10], self.epsilon);
    XCTAssertEqualWithAccuracy(9.74768136075e-06, samples[11], self.epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00451428350061, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00532276649028, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(0.00374535471201, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(0.00411266554147, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(0.000942283542827, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.00170362228528, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[11], epsilon);
  }

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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0715493783355, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0556658469141, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(0.00834430195391, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0103608714417, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
  }

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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0715493783355, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0556658469141, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0167881231755, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(0.018545711413, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
  }

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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0715493783355, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.0556658469141, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(0.0, samples[3], self.epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0.0, samples[0], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00352061167359, samples[1], self.epsilon);
    XCTAssertEqualWithAccuracy(-0.00512139173225, samples[2], self.epsilon);
    XCTAssertEqualWithAccuracy(-3.27081615978e-05, samples[3], self.epsilon);
  }

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
