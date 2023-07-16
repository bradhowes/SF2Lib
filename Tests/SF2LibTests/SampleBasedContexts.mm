// Copyright © 2021 Brad Howes. All rights reserved.
//

#include <AVFoundation/AVFoundation.h>
#import "SF2Lib/Configuration.h"

#include "SampleBasedContexts.hpp"
#include "TestResources.h"

using namespace SF2;
using namespace SF2::Render;

NSURL* PresetTestContextBase::getUrl(int urlIndex)
{
  return [TestResources getResourceUrl:urlIndex];
}

bool PresetTestContextBase::playAudioInTests() {
#if PLAY_AUDIO
  bool playAudio = YES;
#else
  bool playAudio = Configuration.shared.testsPlayAudio;
#endif
  return playAudio;
}

@implementation SamplePlayingTestCase

- (NSString *)pathForTemporaryFile
{
  CFUUIDRef uuid = CFUUIDCreate(NULL);
  assert(uuid != NULL);

  CFStringRef uuidStr = CFUUIDCreateString(NULL, uuid);
  assert(uuidStr != NULL);

  NSString* result = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.caf", uuidStr]];
  assert(result != nil);

  CFRelease(uuidStr);
  CFRelease(uuid);

  return result;
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
  [[NSFileManager defaultManager] removeItemAtPath:[self.audioFileURL path]  error:NULL];
  [self.playedAudioExpectation fulfill];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError * __nullable)error {
  [[NSFileManager defaultManager] removeItemAtPath:[self.audioFileURL path]  error:NULL];
}

- (void)playSamples:(AVAudioPCMBuffer*)buffer count:(int)sampleCount
{
  if (!PresetTestContextBase::playAudioInTests()) return;

  buffer.frameLength = sampleCount;

  NSError* error = nil;
  self.audioFileURL = [NSURL fileURLWithPath: [self pathForTemporaryFile] isDirectory:NO];
  NSDictionary* settings = [[buffer format] settings];
  // NSLog(@"%@", [settings description]);
  [settings setValue:0 forKey:@"AVLinearPCMIsNonInterleaved"];
  AVAudioFile* audioFile = [[AVAudioFile alloc] initForWriting:self.audioFileURL
                                                      settings:settings
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
  self.playedAudioExpectation = [self expectationWithDescription:@"AVAudioPlayer finished"];
  [self.player play];
  [self waitForExpectationsWithTimeout:30.0 handler:^(NSError *err) {
    if (err) {
      XCTFail(@"Expectation Failed with error: %@", err);
    }
  }];
}

AVAudioPCMBuffer* makeBuffer(AVAudioFormat* format, int sampleCount) {
  AVAudioPCMBuffer* buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  AudioBufferList* bufferList = buffer.mutableAudioBufferList;

  for (int index = 0; index < format.channelCount; ++index) {
    UInt32 byteCount = sampleCount * sizeof(AUValue);
    bufferList->mBuffers[index].mDataByteSize = byteCount;
    memset(bufferList->mBuffers[index].mData, 0, byteCount);
  }

  return buffer;
}

- (AVAudioPCMBuffer*)allocateBuffer:(SF2::Float)sampleRate numberOfChannels:(int)channels capacity:(int)sampleCount {
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:channels];
  return makeBuffer(format, sampleCount);
}

- (AVAudioPCMBuffer*)allocateBufferFor:(const TestVoiceCollection&)voices capacity:(int)sampleCount {
  int channelCount = int(voices.count());
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:voices.sampleRate()
                                                                         channels:channelCount];
  return makeBuffer(format, sampleCount);
}

- (size_t)renderInto:(AVAudioPCMBuffer*)buffer
                mono:(SF2::Render::Voice::Voice&)voice
            forCount:(size_t)sampleCount
          startingAt:(size_t)offset
{
  AUValue* ptr = [buffer left] + offset;
  for (auto index = 0; index < sampleCount; ++index) {
    auto sample = voice.renderSample(offset == 45600 && index < 3);
    *ptr++ += sample;
  }
  return offset + sampleCount;
}

- (size_t)renderInto:(AVAudioPCMBuffer*)buffer
              voices:(TestVoiceCollection&)voices
            forCount:(size_t)sampleCount
          startingAt:(size_t)offset
{
  for (size_t channel = 0; channel < voices.count(); ++channel) {
    auto into = [buffer channel: channel] + offset;
    auto& voice{voices[channel]};
    for (auto index = 0; index < sampleCount; ++index) {
      *into++ += voice.renderSample();
    }
  }
  return offset + sampleCount;
}

- (size_t)renderInto:(AVAudioPCMBuffer*)buffer
              voices:(TestVoiceCollection&)voices
            forCount:(size_t)sampleCount
          startingAt:(size_t)offset
   afterRenderSample:(void (^)(size_t))block
{
  for (size_t channel = 0; channel < voices.count(); ++channel) {
    auto into = [buffer channel:channel] + offset;
    auto& voice{voices[channel]};
    for (auto index = 0; index < sampleCount; ++index) {
      *into++ += voice.renderSample();
      block(index + offset);
    }
  }
  return offset + sampleCount;
}

- (size_t)renderInto:(AVAudioPCMBuffer*)buffer
                left:(SF2::Render::Voice::Voice&)left
               right:(SF2::Render::Voice::Voice&)right
            forCount:(size_t)sampleCount
          startingAt:(size_t)offset
{
  AUValue* samplesLeft = [buffer left] + offset;
  AUValue* samplesRight = [buffer right] + offset;
  for (auto index = 0; index < sampleCount; ++index) {
    *samplesLeft++ += left.renderSample();
    *samplesRight++ += right.renderSample();
  }
  return offset + sampleCount;
}

- (void)dumpPresets:(const SF2::IO::File&)file
{
  for (size_t index = 0; index < file.presets().size(); ++index) {
    std::cout << index << ' ' << file.presets()[index].name() << '\n';
  }
}


- (void)dumpSamples:(const std::vector<AUValue>&)samples
{
  std::cout << std::setprecision(12);
  for (size_t index = 0; index < samples.size(); ++index) {
    std::cout << index << ' ' << samples[index] << '\n';
  }
}

@end

@implementation AVAudioPCMBuffer(Accessors)

- (void)normalize:(size_t)voices {
  for (int channel = 0; channel < self.format.channelCount; ++channel) {
    auto count = self.mutableAudioBufferList->mBuffers[channel].mDataByteSize / sizeof(AUValue);
    auto ptr = (AUValue*)(self.mutableAudioBufferList->mBuffers[channel].mData);
    while (count-- > 0) {
      *ptr++ /= AUValue(voices);
    }
  }
}

- (AUValue*)left {
  return (AUValue*)(self.mutableAudioBufferList->mBuffers[0].mData);
}

- (AUValue*)right {
  return (AUValue*)(self.mutableAudioBufferList->mBuffers[1].mData);
}

- (AUValue*)channel:(size_t)index {
  return (AUValue*)(self.mutableAudioBufferList->mBuffers[index].mData);
}

@end
