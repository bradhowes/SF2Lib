// Copyright © 2022 Brad Howes. All rights reserved.
//

#pragma once

#include <AVFoundation/AVFoundation.h>
#include <XCTest/XCTest.h>

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Engine/PresetCollection.hpp"
#include "SF2Lib/Render/Preset.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

struct TestVoiceCollection {
  TestVoiceCollection(int midiKey, int midiVelocity, SF2::Render::Preset preset, SF2::Float sampleRate,
                      const SF2::MIDI::ChannelState& channelState)
  :
  sampleRate_{sampleRate},
  preset_{preset},
  presetConfigs_{preset_.find(midiKey, midiVelocity)},
  channelState_{channelState},
  voices_{}
  {
    voices_.reserve(presetConfigs_.size());
    for (size_t index = 0; index < presetConfigs_.size(); ++index) {
      voices_.emplace_back(sampleRate_, channelState_, index);
      voices_.back().start(presetConfigs_[index]);
    }
  }

  SF2::Float sampleRate() const { return sampleRate_; }
  size_t count() const { return presetConfigs_.size(); }

  void start() {
    for (size_t index = 0; index < presetConfigs_.size(); ++index) {
      voices_[index].start(presetConfigs_[index]);
    }
  }

  void stop() { for (auto& voice : voices_) voice.stop(); }

  void releaseKey() { for (auto& voice : voices_) voice.releaseKey(); }

  SF2::Render::Voice::Voice& operator[](size_t index) { return voices_[index]; }

private:
  SF2::Float sampleRate_;
  SF2::Render::Preset preset_;
  SF2::Render::Preset::ConfigCollection presetConfigs_;
  const SF2::MIDI::ChannelState& channelState_;
  std::vector<SF2::Render::Voice::Voice> voices_;
};

struct PresetTestContextBase
{
  static constexpr SF2::Float epsilonValue() {
    if constexpr (std::is_same_v<SF2::Float, float>) {
      return 1.0e-3;
    } else {
      return 1.0e-12;
    }
  }

  static inline const SF2::Float epsilon = epsilonValue();
  static NSURL* getUrl(int urlIndex);
  static bool playAudioInTests();

  PresetTestContextBase(int urlIndex, SF2::Float sampleRate)
  :
  url_{getUrl(urlIndex)},
  file_{url_.path.UTF8String},
  presets_{},
  sampleRate_{sampleRate}
  {
    presets_.build(file_);
  }

  const SF2::Render::Preset& preset(int presetIndex) const { return presets_[presetIndex]; }

  TestVoiceCollection makeVoiceCollection(int presetIndex, int midiNote, int midiVelocity) {
    channelState_.reset();
    return {midiNote, midiVelocity, preset(presetIndex), sampleRate_, channelState_};
  }

  std::vector<TestVoiceCollection> makeVoicesCollection(int presetIndex, const std::vector<int>& midiNotes, int midiVelocity) {
    std::vector<TestVoiceCollection> notes;
    for (auto midiNote : midiNotes) {
      notes.emplace_back(makeVoiceCollection(presetIndex, midiNote, midiVelocity));
    }
    return notes;
  }

  SF2::Render::Voice::State::State makeState(const SF2::Render::Voice::State::Config& config) const {
    SF2::Render::Voice::State::State state(sampleRate_, channelState_);
    state.prepareForVoice(config);
    return state;
  }

  SF2::Render::Voice::State::State makeState(int presetIndex, int midiKey, int midiVelocity) const {
    assert(url_);
    auto found{preset(presetIndex).find(midiKey, midiVelocity)};
    return makeState(found[0]);
  }

  const NSURL* url() const { return url_; }
  const SF2::IO::File& file() const { return file_; }
  SF2::Float sampleRate() const { return sampleRate_; }

  /// @return open file descriptor to the SF2 file
  int fd() const { return ::open(url_.path.UTF8String, O_RDONLY); }

  NSURL* url_;
  SF2::IO::File file_;
  SF2::Render::Engine::PresetCollection presets_;
  SF2::MIDI::ChannelState channelState_;
  SF2::Float sampleRate_;
};

/**
 Test harness for working with presets in SF2 files. Lazily creates test contexts. The template parameter UrlIndex is
 an integer index into `SF2Files.allResources` which is a list of SF2 files that are available to read.
 */
template <int UrlIndex>
struct PresetTestContext : PresetTestContextBase
{
  PresetTestContext(SF2::Float sampleRate = 48000.0) :
  PresetTestContextBase(UrlIndex, sampleRate)
  {}

  static void SamplesEqual(SF2::Float a, SF2::Float b) {
    XCTAssertEqualWithAccuracy(a, b, PresetTestContextBase::epsilon);
  }
};

struct SampleBasedContexts {
  PresetTestContext<0> context0;
  PresetTestContext<1> context1;
  PresetTestContext<2> context2;
};

@interface SamplePlayingTestCase : XCTestCase <AVAudioPlayerDelegate> {
  SampleBasedContexts contexts;
}

@property (nonatomic, retain) AVAudioPlayer* player;
@property (nonatomic, retain) XCTestExpectation* playedAudioExpectation;
@property (nonatomic, retain) NSURL* audioFileURL;
@property (nonatomic, retain) AVAudioPCMBuffer* buffer;

- (void)playSamples:(AVAudioPCMBuffer*)buffer count:(int)sampleCount;

- (AVAudioPCMBuffer*)allocateBufferFor:(const TestVoiceCollection&)voices capacity:(int)sampleCount;
- (AVAudioPCMBuffer*)allocateBuffer:(SF2::Float)sampleRate numberOfChannels:(int)channels capacity:(int)sampleCount;

- (size_t)renderInto:(AVAudioPCMBuffer*)buffer mono:(SF2::Render::Voice::Voice&)left forCount:(size_t)sampleCount startingAt:(size_t)offset;
- (size_t)renderInto:(AVAudioPCMBuffer*)buffer left:(SF2::Render::Voice::Voice&)left right:(SF2::Render::Voice::Voice&)right forCount:(size_t)sampleCount startingAt:(size_t)offset;
- (size_t)renderInto:(AVAudioPCMBuffer*)buffer voices:(TestVoiceCollection&)voices forCount:(size_t)sampleCount startingAt:(size_t)offset;
- (size_t)renderInto:(AVAudioPCMBuffer*)buffer voices:(TestVoiceCollection&)voices forCount:(size_t)sampleCount startingAt:(size_t)offset afterRenderSample:(void (^)(size_t))block;

- (void)dumpPresets:(const SF2::IO::File&)file;
- (void)dumpSamples:(const std::vector<AUValue>&)samples;

@end

@interface AVAudioPCMBuffer(Accessors)

- (AUValue*)left;
- (AUValue*)right;
- (AUValue*)channel:(size_t)index;
- (void)normalize:(size_t)voiceCount;

@end
