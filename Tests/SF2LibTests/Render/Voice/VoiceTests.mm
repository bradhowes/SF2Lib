// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Types.hpp"

static SF2::Float epsilon = 1.0e-8;

#include <AVFoundation/AVFoundation.h>
#include <iostream>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Render/Preset.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

using namespace SF2;
using namespace SF2::Render;

@interface VoiceTests : XCTestCase <AVAudioPlayerDelegate>
@property (nonatomic) bool playAudio;
@property (nonatomic, retain) AVAudioPlayer* player;
@property (nonatomic, retain) XCTestExpectation* expectation;
@property (nonatomic, retain) NSURL* audioFileURL;
@end

@implementation VoiceTests {
  SampleBasedContexts contexts;
}

- (void)setUp {
  // See Package.swift
#if PLAY_AUDIO
  self.playAudio = YES;
#else
  self.playAudio = NO;
#endif
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
  [[NSFileManager defaultManager] removeItemAtPath:[self.audioFileURL path]  error:NULL];
  [self.expectation fulfill];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error {
  [[NSFileManager defaultManager] removeItemAtPath:[self.audioFileURL path]  error:NULL];
}

- (void)testRolandPianoRender {
  const auto& file = contexts.context2.file();

  MIDI::ChannelState channelState;
  MIDI::NRPN nrpn{channelState};
  InstrumentCollection instruments(file);
  Preset preset(file, instruments, file.presets()[0]);

  auto found = preset.find(69, 127);
  XCTAssertEqual(found.size(), 2);
  Voice::Voice v1L{44100, channelState, 0};
  v1L.configure(found[0], nrpn);
  Voice::Voice v1R{44100, channelState, 1};
  v1R.configure(found[1], nrpn);

  found = preset.find(73, 127);
  XCTAssertEqual(found.size(), 2);
  Voice::Voice v2L{44100, channelState, 2};
  v2L.configure(found[0], nrpn);
  Voice::Voice v2R{44100, channelState, 3};
  v2R.configure(found[1], nrpn);

  found = preset.find(76, 127);
  XCTAssertEqual(found.size(), 2);
  Voice::Voice v3L{44100, channelState, 4};
  v3L.configure(found[0], nrpn);
  Voice::Voice v3R{44100, channelState, 5};
  v3R.configure(found[1], nrpn);

  Float sampleRate = 44100.0;
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  int seconds = 1;
  int sampleCount = sampleRate * seconds;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  AudioBufferList* bufferList = buffer.mutableAudioBufferList;
  bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(float);
  bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(float);
  float* samplesLeft = (float*)(bufferList->mBuffers[0].mData);
  float* samplesRight = (float*)(bufferList->mBuffers[1].mData);

  size_t keyReleaseCount{size_t(sampleCount / 4)};
  size_t voiceSampleCount{size_t(sampleCount / 3)};
  std::vector<AUValue> samples;

  auto renderLR = [&](auto& left, auto& right, bool dump = false) {
    for (auto index = 0; index < voiceSampleCount; ++index) {
      AUValue sample = left.renderSample();
      if (dump) std::cout << sample << '\n';
      *samplesLeft++ = sample;
      *samplesRight++ = right.renderSample();
      if (index == 0 || index == voiceSampleCount - 1) {
        samples.push_back(sample);
      }
      else if (index == keyReleaseCount) {
        samples.push_back(sample);
        left.releaseKey();
        right.releaseKey();
      }
    }
  };

  renderLR(v1L, v1R);
  renderLR(v2L, v2R);
  renderLR(v3L, v3R);

  std::cout << std::setprecision(10);
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
    XCTAssertEqualWithAccuracy( 0.0000000000, samples[0], epsilon);
    XCTAssertEqualWithAccuracy(-0.1943116635, samples[1], epsilon);
    XCTAssertEqualWithAccuracy( 0.07495743781, samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.00000000000, samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.07910773903, samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 0.04327972978, samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.00000000000, samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 0.08214084059, samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.01485970616, samples[8], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testOrganRender {
  const auto& file = contexts.context0.file();

  MIDI::ChannelState channelState;
  MIDI::NRPN nrpn{channelState};
  InstrumentCollection instruments(file);
  Preset preset(file, instruments, file.presets()[89]);

  auto found = preset.find(64, 127);
  Voice::Voice v1{44100, channelState, 0};
  v1.configure(found[0], nrpn);

  found = preset.find(68, 127);
  Voice::Voice v2{44100, channelState, 2};
  v2.configure(found[0], nrpn);

  found = preset.find(71, 127);
  Voice::Voice v3{44100, channelState, 4};
  v3.configure(found[0], nrpn);

  double sampleRate = 44100.0;
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  int seconds = 10;
  int sampleCount = sampleRate * seconds;
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  AudioBufferList* bufferList = buffer.mutableAudioBufferList;
  bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(Float);
  bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(Float);
  float* samplesLeft = (float*)(bufferList->mBuffers[0].mData);
  float* samplesRight = (float*)(bufferList->mBuffers[1].mData);

  std::vector<AUValue> samples;
  for (auto index = 0; index < sampleCount; ++index) {
    auto s1 = v1.renderSample();
    auto s2 = v2.renderSample();
    auto s3 = v3.renderSample();

    AUValue s = (s1 + s2 + s3) / 3.0;
    *samplesLeft++ = s;
    *samplesRight++ = s;

    if (index == 0 || index == sampleCount - 1) {
      samples.push_back(s1);
      samples.push_back(s2);
      samples.push_back(s3);
    }
    else if (index == int(sampleCount * 0.3)) {
      // Enable vibrato
      v1.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, 100);
      v2.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, 100);
      v3.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, 100);
    }
    else if (index == int(sampleCount * 0.5)) {
      // Disable vibrato
      v1.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, 0);
      v2.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, 0);
      v3.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, 0);
    }
    else if (index == int(sampleCount * 0.7)) {
      samples.push_back(s1);
      samples.push_back(s2);
      samples.push_back(s3);

      v1.releaseKey();
      v2.releaseKey();
      v3.releaseKey();
    }
  }

  std::cout << std::setprecision(10);
  for (auto index = 0; index < 9; ++index) {
    std::cout << index << ' ' << samples[index] << '\n';
  }

  XCTAssertEqual(9, samples.size());
  XCTAssertEqualWithAccuracy(0.0, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[2], epsilon);

  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(-0.02659720555, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(-0.08138652891, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0973405987, samples[5], epsilon);
  }
  else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(-0.02687120624, samples[3], epsilon);
    XCTAssertEqualWithAccuracy(-0.08148908615, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.09712578356, samples[5], epsilon);
  }

  XCTAssertEqualWithAccuracy(0.0, samples[6], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[8], epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)playSamples:(AVAudioPCMBuffer*)buffer count:(int)sampleCount
{
  if (!self.playAudio) return;

  buffer.frameLength = sampleCount;

  NSError* error = nil;
  self.audioFileURL = [NSURL fileURLWithPath: [self pathForTemporaryFile] isDirectory:NO];
  AVAudioFile* audioFile = [[AVAudioFile alloc] initForWriting:self.audioFileURL
                                                      settings:[[buffer format] settings]
                                                  commonFormat:AVAudioPCMFormatFloat32
                                                   interleaved:false
                                                         error:&error];
  if (error) {
    XCTFail(@"failed with error: %@", error);
    return;
  }

  [audioFile writeFromBuffer:buffer error:&error];
  if (error) {
    XCTFail(@"failed with error: %@", error);
    return;
  }

  audioFile = nil;

  self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:self.audioFileURL error:&error];
  if (self.player == nullptr && error != nullptr) {
    XCTFail(@"Expectation Failed with error: %@", error);
    return;
  }

  self.player.delegate = self;
  self.expectation = [self expectationWithDescription:@"AVAudioPlayer finished"];
  [self.player play];
  [self waitForExpectationsWithTimeout:30.0 handler:^(NSError *err) {
    if (err) {
      XCTFail(@"Expectation Failed with error: %@", err);
    }
  }];
}

- (NSString *)pathForTemporaryFile
{
  NSString *  result;
  CFUUIDRef   uuid;
  CFStringRef uuidStr;

  uuid = CFUUIDCreate(NULL);
  assert(uuid != NULL);

  uuidStr = CFUUIDCreateString(NULL, uuid);
  assert(uuidStr != NULL);

  result = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.caf", uuidStr]];
  assert(result != nil);

  CFRelease(uuidStr);
  CFRelease(uuid);

  return result;
}

- (void)testLoopingModes {
  Voice::State::State state{contexts.context2.makeState(60, 32)};
  Voice::Voice voice{44100.0, contexts.context2.channelState(), 0};

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
