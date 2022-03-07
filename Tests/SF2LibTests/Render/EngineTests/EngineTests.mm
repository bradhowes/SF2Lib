// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <iostream>

#include <XCTest/XCTest.h>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Render/Engine/Engine.hpp"

using namespace SF2;
using namespace SF2::Render::Engine;

@interface EngineTests : XCTestCase <AVAudioPlayerDelegate>
@property (nonatomic) bool playAudio;
@property (nonatomic, retain) AVAudioPlayer* player;
@property (nonatomic, retain) XCTestExpectation* expectation;
@property (nonatomic, retain) NSURL* audioFileURL;
@end

@implementation EngineTests {
  SampleBasedContexts contexts;
  SF2::Render::Voice::Sample::Generator::Interpolator interpolator;
}

- (void)setUp {
  // See Package.swift
  interpolator = SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder;
#if PLAY_AUDIO
  self.playAudio = YES;
#else
  self.playAudio = NO;
#endif
}

- (void)testInit {
  Engine<32> engine(44100.0, interpolator);
  XCTAssertEqual(engine.maxVoiceCount, 32);
  XCTAssertEqual(engine.activeVoiceCount(), 0);
}

- (void)testLoad {
  Engine<32> engine(44100.0, interpolator);
  engine.load(contexts.context0.file());
  XCTAssertEqual(engine.presetCount(), 235);
}

- (void)testUsePreset {
  Engine<32> engine(44100.0, interpolator);
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
  [[NSFileManager defaultManager] removeItemAtPath:[self.audioFileURL path]  error:NULL];
  [self.expectation fulfill];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error {
  [[NSFileManager defaultManager] removeItemAtPath:[self.audioFileURL path]  error:NULL];
}

- (void)testRolandPianoChordRenderLinear {
  Float sampleRate{44100.0};
  Engine<32> engine(sampleRate, SF2::Render::Voice::Sample::Generator::Interpolator::linear);

  engine.load(contexts.context2.file());
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  AUAudioFrameCount frameCount = 512;
  engine.setRenderingFormat(format, frameCount);

  int seconds = 6;
  int sampleCount = sampleRate * seconds;
  int frames = sampleCount / frameCount;
  int remaining = sampleCount - frames * frameCount;
  int noteOnFrame = 10;
  int noteOnDuration = 50;
  int noteOffFrame = noteOnFrame + noteOnDuration;

  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  assert(buffer != nullptr);

  AudioBufferList* bufferList = buffer.mutableAudioBufferList;
  bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(float);
  bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(float);

  float* samplesLeft = (float*)(bufferList->mBuffers[0].mData);
  float* samplesRight = (float*)(bufferList->mBuffers[1].mData);

  XCTAssertEqual(0, engine.activeVoiceCount());

  int frameIndex = 0;
  auto renderUntil = [&](int until) {
    while (frameIndex++ < until) {
      engine.render(samplesLeft, samplesRight, frameCount);
      samplesLeft += frameCount;
      samplesRight += frameCount;
    }
  };

  auto playChord = [&](int note1, int note2, int note3) {
    renderUntil(noteOnFrame);
    engine.noteOn(note1, 64);
    engine.noteOn(note2, 64);
    engine.noteOn(note3, 64);
    renderUntil(noteOffFrame);
    engine.noteOff(note1);
    engine.noteOff(note2);
    engine.noteOff(note3);
    noteOnFrame += noteOnDuration;
    noteOffFrame += noteOnDuration;
  };

  playChord(60, 64, 67);
  playChord(60, 65, 69);
  playChord(60, 64, 67);
  playChord(59, 62, 67);
  playChord(60, 64, 67);

  renderUntil(frameCount);
  if (remaining > 0) {
    engine.render(samplesLeft, samplesRight, remaining);
    samplesLeft += remaining;
    samplesRight += remaining;
  }

  XCTAssertEqual(2, engine.activeVoiceCount());

  [self playSamples: buffer count: sampleCount];
}

- (void)testRolandPianoChordRenderCubic4thOrder {
  Float sampleRate{44100.0};
  Engine<32> engine(sampleRate, SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder);

  engine.load(contexts.context2.file());
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  AUAudioFrameCount frameCount = 512;
  engine.setRenderingFormat(format, frameCount);

  int seconds = 6;
  int sampleCount = sampleRate * seconds;
  int frames = sampleCount / frameCount;
  int remaining = sampleCount - frames * frameCount;
  int noteOnFrame = 10;
  int noteOnDuration = 50;
  int noteOffFrame = noteOnFrame + noteOnDuration;

  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  assert(buffer != nullptr);

  AudioBufferList* bufferList = buffer.mutableAudioBufferList;
  bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(float);
  bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(float);

  float* samplesLeft = (float*)(bufferList->mBuffers[0].mData);
  float* samplesRight = (float*)(bufferList->mBuffers[1].mData);

  XCTAssertEqual(0, engine.activeVoiceCount());

  int frameIndex = 0;
  auto renderUntil = [&](int until) {
    while (frameIndex++ < until) {
      engine.render(samplesLeft, samplesRight, frameCount);
      samplesLeft += frameCount;
      samplesRight += frameCount;
    }
  };

  auto playChord = [&](int note1, int note2, int note3) {
    renderUntil(noteOnFrame);
    engine.noteOn(note1, 64);
    engine.noteOn(note2, 64);
    engine.noteOn(note3, 64);
    renderUntil(noteOffFrame);
    engine.noteOff(note1);
    engine.noteOff(note2);
    engine.noteOff(note3);
    noteOnFrame += noteOnDuration;
    noteOffFrame += noteOnDuration;
  };

  playChord(60, 64, 67);
  playChord(60, 65, 69);
  playChord(60, 64, 67);
  playChord(59, 62, 67);
  playChord(60, 64, 67);

  renderUntil(frameCount);
  if (remaining > 0) {
    engine.render(samplesLeft, samplesRight, remaining);
    samplesLeft += remaining;
    samplesRight += remaining;
  }

  XCTAssertEqual(2, engine.activeVoiceCount());

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

@end
