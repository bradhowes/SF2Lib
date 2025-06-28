// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>

#include <iomanip>
#include <iostream>

#include "SampleBasedContexts.hpp"

#include "SF2Lib/Types.hpp"
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
  // self.playAudio = NO;
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputRolandPiano {
  auto harness{TestEngineHarness{48000.0, 96, SF2::Render::Voice::Sample::Interpolator::cubic4thOrder}};
  auto& engine{harness.engine()};
  harness.load(contexts.context2.path(), 0);

  int seconds = 4;
  int repetitions = 14;
  auto mixer{harness.createMixer(seconds)};

  auto renderCount = harness.renders();
  auto playing = renderCount / 2;
  auto decay = renderCount - playing;

  auto noteOnRenders = playing / repetitions;
  auto runningRenders = AVAudioFrameCount{0};

  std::vector<AUValue> samples;

  auto note = 64;
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
    XCTAssertEqualWithAccuracy(-0.0684094578028, samples[0], epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(-0.0524950399995, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0696591883898, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0291275978088, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-0.0779406502843, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(-0.0192117504776, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0806093290448, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.0183418914676, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(-0.0816504284739, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(-0.0178039055318, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.0816528201103, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.017737198621, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(-0.0817046761513, samples[11], epsilon);
    XCTAssertEqualWithAccuracy(-0.0177110619843, samples[12], epsilon);
    XCTAssertEqualWithAccuracy(-0.0817179381847, samples[13], epsilon);
    XCTAssertEqualWithAccuracy(1.21334733194e-06, samples[14], epsilon);
  }

  [self playSamples: harness.dryBuffer() count: harness.duration()];
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputChimes {
  TestVoiceCollection voices{contexts.context0.makeVoiceCollection(163, 69)};

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
        case 1: XCTAssertEqualWithAccuracy(-0.00258853682317, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy(-0.00033974123653, samples[index], epsilon); break;
      }
    }
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testRolandPianoRender {
  auto notes = contexts.context0.makeVoicesCollection(0, {69, 73, 76});
  int seconds = 1;
  int sampleCount = notes.front().sampleRate() * seconds;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  size_t voiceSampleCount{size_t(sampleCount / 3)};
  size_t keyReleaseCount{size_t(voiceSampleCount * 0.95)};

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
    XCTAssertEqualWithAccuracy(-0.00220142956823, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00214024679735, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.00237721414305, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.000606141693424, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.000649725960102, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0.00271704629995, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.00411727419123, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.00430837459862, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(-0.00325549324043, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testYamahaRender {
  auto notes = contexts.context0.makeVoicesCollection(0, {69, 73, 76});
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.3;
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
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00211101467721, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00226897071116, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.00129580392968, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00148961134255, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.000905494496692, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.00127385149244, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testOrganRender {
  auto notes = contexts.context0.makeVoicesCollection(18, {69, 73, 76});
  int seconds = 2;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.95;
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
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00372831104323, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00373373110779, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.00408017868176, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00413635699078, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.00354059017263, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.00363452685997, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testCelloRenderOneNote {
  auto notes = contexts.context0.makeVoicesCollection(42, {48, 55});
  int seconds = 1.5;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.95;
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

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.00364254624583, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.00210017827339, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.0023496679496, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(-0.00281907012686, samples[4], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.000580907100812, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.00081623432925, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0.00114000437316, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0.00275608664379, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00592460669577, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(-0.00544966896996, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(-0.00484692770988, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(0.00402548583224, samples[9], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderChord {
  auto notes = contexts.context0.makeVoicesCollection(49, {76, 79, 83});
  int seconds = 2.0;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.5;
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
    XCTAssertEqualWithAccuracy(-0.0114827128127, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0128602702171, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-2.80974309135e-05, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0036832485348, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.0148050673306, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(7.29637031327e-05, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.00607153633609, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.0186297148466, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(8.02424619906e-05, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithVibrato {
  auto notes = contexts.context0.makeVoicesCollection(49, {76, 79, 83});
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  size_t keyReleaseCount = sampleCount * 0.95;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;
  for (auto& note : notes) {
    note.start();
    [self renderInto:buffer voices:note forCount: keyReleaseCount startingAt: 0 afterRenderSample:^(size_t index) {
      int vibrato = int(100.0 * index / sampleCount);
      sst.setValue(note[0].state(), Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    }];

    note.releaseKey();

    [self renderInto:buffer voices:note forCount: sampleCount - keyReleaseCount startingAt: keyReleaseCount afterRenderSample:^(size_t index) {
      int vibrato = int(100.0 * index / sampleCount);
      sst.setValue(note[0].state(), Voice::State::State::Index::vibratoLFOToPitch, vibrato);
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
    XCTAssertEqualWithAccuracy(-0.00757760647684, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00681708240882, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-0.000654317671433, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0049174753949, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(-0.00293870223686, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(-0.00312492344528, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.00999075360596, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.00619829911739, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(-0.00358576886356, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWithSlowAttackRelease {
  auto notes = contexts.context0.makeVoicesCollection(40, {64, 68, 71});
  int seconds = 3;
  int sampleCount = notes.front().sampleRate() * seconds;
  int keyReleaseCount = sampleCount * 0.5;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  // Configure note to take 1.5s to attack and release
  for (auto& note : notes) {
    for (auto voiceIndex = 0; voiceIndex < note.count(); ++voiceIndex) {
      sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::attackVolumeEnvelope, DSP::secondsToCents(1.5));
      sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::releaseVolumeEnvelope, DSP::secondsToCents(1.5));
      sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::sampleModes, 1);
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
    XCTAssertEqualWithAccuracy(-0.00469431607053, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00508148036897, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(0.00361827807501, samples[5], epsilon);
    XCTAssertEqualWithAccuracy(0.00423853099346, samples[6], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[7], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[8], epsilon);
    XCTAssertEqualWithAccuracy(-0.00137585343327, samples[9], epsilon);
    XCTAssertEqualWithAccuracy(-0.00265919230878, samples[10], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[11], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testSlowAttackRelease {
  auto notes = contexts.context0.makeVoicesCollection(197, {64});
  int seconds = 4;
  int sampleCount = notes.front().sampleRate() * seconds;
  int keyReleaseCount = sampleCount * 0.5;
  AVAudioPCMBuffer* buffer = [self allocateBufferFor:notes.front() capacity:sampleCount];

  std::vector<AUValue> samples;

  for (auto& note : notes) {

    for (auto voiceIndex = 0; voiceIndex < note.count(); ++voiceIndex) {
      // Configure volume envelope for 2s attack.
      sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::attackVolumeEnvelope, 1200);
      sst.setAdjustment(note[voiceIndex].state(), Voice::State::State::Index::attackVolumeEnvelope, 0);
      // Configure volume envelope for 2s release.
      sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::releaseVolumeEnvelope, 1200);
      sst.setAdjustment(note[voiceIndex].state(), Voice::State::State::Index::releaseVolumeEnvelope, 0);
      // Configure sample generator to loop until volume envelope is done.
      sst.setValue(note[voiceIndex].state(), Voice::State::State::Index::sampleModes, 1);
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
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0715493783355, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0556658469141, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.0102065894753, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.0122033078223, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testCelesta {
  auto notes = contexts.context0.makeVoicesCollection(11, {64}, 127);
  auto sampleRate = notes.front().sampleRate();
  int seconds = 2;
  int sampleCount = sampleRate * seconds;
  int keyReleaseCount = sampleCount * 0.25;
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
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0715493783355, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0556658469141, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(0.0169868897647, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(0.0190779417753, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testHarp {
  auto notes = contexts.context0.makeVoicesCollection(46, {76});
  auto sampleRate = notes.front().sampleRate();
  int seconds = 3;
  int sampleCount = sampleRate * seconds;
  int keyReleaseCount = sampleCount * 0.5;
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
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.0715493783355, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.0556658469141, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(0, samples[3], epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.00504647148773, samples[1], epsilon);
    XCTAssertEqualWithAccuracy(-0.00677601760253, samples[2], epsilon);
    XCTAssertEqualWithAccuracy(-2.93661687465e-05, samples[3], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testLoopingModes {
  auto state = contexts.context2.makeVoiceCollection(0, 60);
  auto& voice = state[0];

  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, -1);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, 1);
  XCTAssertEqual(Voice::Voice::LoopingMode::activeEnvelope, voice.loopingMode());
  sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, 2);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
  sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, 3);
  XCTAssertEqual(Voice::Voice::LoopingMode::duringKeyPress, voice.loopingMode());
  sst.setValue(voice.state(), Voice::State::State::Index::sampleModes, 4);
  XCTAssertEqual(Voice::Voice::LoopingMode::none, voice.loopingMode());
}

- (void)testSostenuto {
  auto state = contexts.context0.makeVoiceCollection(0, 60);
  auto& voice = state[0];
  voice.start();
  while (voice.renderSample() == 0.0) ;
  XCTAssertTrue(voice.isKeyDown());
  voice.useSostenuto();
  XCTAssertTrue(voice.isKeyDown());
  voice.renderSample();
  voice.releaseKey({1, {true, true, true}});
  voice.renderSample();
  XCTAssertTrue(voice.isKeyDown());
  voice.releaseKey({0, {false, true, false}});
  voice.renderSample();
  XCTAssertTrue(voice.isKeyDown());
  voice.releaseKey({0, {false, false, false}});
  voice.renderSample();
  XCTAssertFalse(voice.isKeyDown());
}

- (void)testSustain {
  auto state = contexts.context0.makeVoiceCollection(0, 60);
  auto& voice = state[0];
  voice.start();
  XCTAssertTrue(voice.isKeyDown());
  while (voice.renderSample() == 0.0) ;
  voice.releaseKey({1, {true, false, false}});
  voice.renderSample();
  XCTAssertTrue(voice.isKeyDown());
  voice.releaseKey({0, {true, true, true}});
  voice.renderSample();
  XCTAssertTrue(voice.isKeyDown());
  voice.releaseKey({0, {false, true, true}});
  voice.renderSample();
  XCTAssertFalse(voice.isKeyDown());
}

@end
