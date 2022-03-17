// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <iostream>

#include <XCTest/XCTest.h>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.h"
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
  self.playAudio = Configuration.shared.testsPlayAudio;
#endif
}

- (void)testInit {
  Engine engine(44100.0, 32, interpolator);
  XCTAssertEqual(engine.voiceCount(), 32);
  XCTAssertEqual(engine.activeVoiceCount(), 0);
}

- (void)testLoad {
  Engine engine(44100.0, 32, interpolator);
  engine.load(contexts.context0.file(), 0);
  XCTAssertEqual(engine.presetCount(), 235);
}

- (void)testUsePreset {
  Engine engine(44100.0, 32, interpolator);
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
  Engine engine(sampleRate, 32, SF2::Render::Voice::Sample::Generator::Interpolator::linear);

  engine.load(contexts.context2.file(), 0);
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  AUAudioFrameCount frameCount = 512;
  engine.setRenderingFormat(3, format, frameCount);

  int seconds = 6;
  int sampleCount = sampleRate * seconds;
  int frames = sampleCount / frameCount;
  int remaining = sampleCount - frames * frameCount;
  int noteOnFrame = 10;
  int noteOnDuration = 50;
  int noteOffFrame = noteOnFrame + noteOnDuration;

  AVAudioPCMBuffer* dryBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  assert(dryBuffer != nullptr);

  AudioBufferList* bufferList = dryBuffer.mutableAudioBufferList;
  bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(AUValue);
  bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(AUValue);
  DSPHeaders::BusBuffers dry({(AUValue*)(bufferList->mBuffers[0].mData), (AUValue*)(bufferList->mBuffers[1].mData)});
  DSPHeaders::BusBuffers chorus({});
  DSPHeaders::BusBuffers reverb({});
  Mixer mixer{dry, chorus, reverb};

  XCTAssertEqual(0, engine.activeVoiceCount());

  int frameIndex = 0;
  auto renderUntil = [&](int until) {
    while (frameIndex++ < until) {
      engine.renderInto(mixer, frameCount);
      mixer.shiftOver(frameCount);
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
    engine.renderInto(mixer, frameCount);
  }

  XCTAssertEqual(2, engine.activeVoiceCount());

  [self playSamples: dryBuffer count: sampleCount];
}

- (void)testRolandPianoChordRenderCubic4thOrder {
  Float sampleRate{44100.0};
  AUAudioFrameCount frameCount = 512;
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  Engine engine(sampleRate, 32, SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder);
  engine.load(contexts.context2.file(), 0);
  engine.setRenderingFormat(3, format, frameCount);

  // Set NPRN state so that voices send 20% output to the chorus channel
  engine.nprn().process(MIDI::ControlChange::nprnMSB, 120);
  engine.nprn().process(MIDI::ControlChange::nprnLSB, int(Entity::Generator::Index::chorusEffectSend));
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
  engine.nprn().process(MIDI::ControlChange::dataEntryMSB, 65);

  int seconds = 6;
  int sampleCount = sampleRate * seconds;
  int frames = sampleCount / frameCount;
  int remaining = sampleCount - frames * frameCount;
  int noteOnFrame = 10;
  int noteOnDuration = 50;
  int noteOffFrame = noteOnFrame + noteOnDuration;

  AVAudioPCMBuffer* dryBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  assert(dryBuffer != nullptr);

  AudioBufferList* bufferList = dryBuffer.mutableAudioBufferList;
  bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(AUValue);
  bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(AUValue);

  DSPHeaders::BusBuffers dry({(AUValue*)(bufferList->mBuffers[0].mData), (AUValue*)(bufferList->mBuffers[1].mData)});

  AVAudioPCMBuffer* chorusBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  assert(chorusBuffer != nullptr);

  bufferList = chorusBuffer.mutableAudioBufferList;
  bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(AUValue);
  bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(AUValue);

  DSPHeaders::BusBuffers chorus({(AUValue*)(bufferList->mBuffers[0].mData), (AUValue*)(bufferList->mBuffers[1].mData)});
  DSPHeaders::BusBuffers reverb({});
  Mixer mixer{dry, chorus, reverb};

  XCTAssertEqual(0, engine.activeVoiceCount());

  int frameIndex = 0;
  auto renderUntil = [&](int until) {
    while (frameIndex++ < until) {
      engine.renderInto(mixer, frameCount);
      mixer.shiftOver(frameCount);
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
    engine.renderInto(mixer, frameCount);
  }

  XCTAssertEqual(2, engine.activeVoiceCount());

  [self playSamples: dryBuffer count: sampleCount];
  [self playSamples: chorusBuffer count: sampleCount];
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

// Render 1 second of audio at 44100.0 sample rate using all voices of an engine and interpolating using 4th-order cubic.
// Uses both effects buffers to account for mixing effort when they are active.
- (void)testEngineRenderPerformance
{
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    Float sampleRate{44100.0};
    AUAudioFrameCount frameCount = 512;
    AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

    Engine engine(sampleRate, 32, SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder);
    engine.load(contexts.context2.file(), 0);
    engine.setRenderingFormat(3, format, frameCount);

    // Set NPRN state so that voices send 20% output to the chorus channel
    engine.nprn().process(MIDI::ControlChange::nprnMSB, 120);
    engine.nprn().process(MIDI::ControlChange::nprnLSB, int(Entity::Generator::Index::chorusEffectSend));
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
    engine.nprn().process(MIDI::ControlChange::dataEntryMSB, 65);

    // Set NPRN state so that voices send 10% output to the reverb channel
    engine.nprn().process(MIDI::ControlChange::nprnMSB, 120);
    engine.nprn().process(MIDI::ControlChange::nprnLSB, int(Entity::Generator::Index::reverbEffectSend));
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 100);
    engine.nprn().process(MIDI::ControlChange::dataEntryMSB, 64);

    int seconds = 1;
    int sampleCount = sampleRate * seconds;
    int frames = sampleCount / frameCount;
    int remaining = sampleCount - frames * frameCount;

    AVAudioPCMBuffer* dryBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
    assert(dryBuffer != nullptr);

    AudioBufferList* bufferList = dryBuffer.mutableAudioBufferList;
    bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(float);
    bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(float);

    DSPHeaders::BusBuffers dry({(float*)(bufferList->mBuffers[0].mData), (float*)(bufferList->mBuffers[1].mData)});

    AVAudioPCMBuffer* chorusBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
    assert(chorusBuffer != nullptr);

    bufferList = chorusBuffer.mutableAudioBufferList;
    bufferList->mBuffers[0].mDataByteSize = sampleCount * sizeof(float);
    bufferList->mBuffers[1].mDataByteSize = sampleCount * sizeof(float);

    DSPHeaders::BusBuffers chorus({(float*)(bufferList->mBuffers[0].mData), (float*)(bufferList->mBuffers[1].mData)});
    DSPHeaders::BusBuffers reverb({});
    Mixer mixer{dry, chorus, reverb};

    for (int voice = 0; voice < engine.voiceCount(); ++voice) {
      engine.noteOn(32 + 2 * voice, 64);
    }

    [self startMeasuring];
    for (auto frameIndex = 0; frameIndex < frames; ++frameIndex) {
      engine.renderInto(mixer, frameCount);
    }
    [self stopMeasuring];
  }];
}

@end
