// Copyright © 2022 Brad Howes. All rights reserved.
//

#pragma once

#include <iomanip>
#include <AVFoundation/AVFoundation.h>
#include <XCTest/XCTest.h>

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/Mixer.hpp"
#include "SF2Lib/Render/Engine/Parameters.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"
#include "SF2Lib/Render/Preset.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

#include "SF2Lib/DSPHeaders/BusBufferFacet.hpp"

struct TestEngineHarness {
  using Engine = SF2::Render::Engine::Engine;
  using Mixer = SF2::Render::Engine::Mixer;
  using Interpolator = SF2::Render::Voice::Sample::Interpolator;

  TestEngineHarness(SF2::Float sampleRate, size_t voiceCount = 96,
                    Interpolator interpolator = Interpolator::cubic4thOrder) noexcept :
  engine_{sampleRate, voiceCount, interpolator}
  {
    format_ = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];
    engine_.setRenderingFormat(3, format_, 512);
  }

  Mixer createMixer(int seconds) noexcept
  {
    duration_ = seconds * engine_.sampleRate();
    dryBuffer_ = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format_ frameCapacity:duration_];
    dryFacet_.setChannelCount(2);
    dryFacet_.assignBufferList(dryBuffer_.mutableAudioBufferList);
    DSPHeaders::BusBuffers dry{dryFacet_.busBuffers()};

    chorusBuffer_ = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format_ frameCapacity:duration_];
    chorusFacet_.setChannelCount(2);
    chorusFacet_.assignBufferList(chorusBuffer_.mutableAudioBufferList);
    DSPHeaders::BusBuffers chorus{chorusFacet_.busBuffers()};

    reverbBuffer_ = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format_ frameCapacity:duration_];
    reverbFacet_.setChannelCount(2);
    reverbFacet_.assignBufferList(reverbBuffer_.mutableAudioBufferList);
    DSPHeaders::BusBuffers reverb{reverbFacet_.busBuffers()};

    return Mixer(dry, chorus, reverb);
  }

  int renderOnce(Mixer& mixer) noexcept {
    engine_.renderInto(mixer, maxFramesToRender_);
    mixer.shiftOver(maxFramesToRender_);
    return ++renderIndex_;
  }

  void renderUntil(Mixer& mixer, int limit) noexcept {
    while (renderIndex_ < limit) {
      engine_.renderInto(mixer, maxFramesToRender_);
      mixer.shiftOver(maxFramesToRender_);
      ++renderIndex_;
    }
  }

  void renderToEnd(Mixer& mixer) noexcept {
    auto limit = renders();
    while (renderIndex_++ < limit) {
      engine_.renderInto(mixer, maxFramesToRender_);
      mixer.shiftOver(maxFramesToRender_);
    }
    limit = remaining();
    if (limit) engine_.renderInto(mixer, limit);
  }

  Engine& engine() noexcept { return engine_; }

  SF2::IO::File::LoadResponse load(const std::string& path, size_t index) noexcept {
    return engine_.load(path, index);
  }

  void usePresetWithIndex(size_t index) { engine_.usePresetWithIndex(index); }

  void usePresetWithBankProgram(uint16_t bank, uint16_t program) { engine_.usePresetWithBankProgram(bank, program); };

  AVAudioFrameCount maxFramesToRender() const noexcept { return maxFramesToRender_; }

  AVAudioPCMBuffer* dryBuffer() const noexcept { return dryBuffer_; }
  AVAudioPCMBuffer* chorusBuffer() const noexcept { return chorusBuffer_; }
  AVAudioPCMBuffer* reverbBuffer() const noexcept { return reverbBuffer_; }

  AVAudioFrameCount duration() const noexcept { return duration_; }
  AVAudioFrameCount renders() const noexcept { return duration_ / maxFramesToRender_; }
  AVAudioFrameCount remaining() const noexcept { return duration_ - renders() * maxFramesToRender_; }

  AUValue lastDrySample() noexcept { return dryFacet_.busBuffers()[0][-1]; }
  AUValue lastChorusSample() noexcept { return chorusFacet_.busBuffers()[0][-1]; }
  AUValue lastReverbSample() noexcept { return reverbFacet_.busBuffers()[0][-1]; }

  AUValue lastDrySample(int channel) noexcept { return dryFacet_.busBuffers()[channel][-1]; }
  AUValue lastChorusSample(int channel) noexcept { return chorusFacet_.busBuffers()[channel][-1]; }
  AUValue lastReverbSample(int channel) noexcept { return reverbFacet_.busBuffers()[channel][-1]; }

  template <typename T>
  void sendRaw(const T& command) noexcept {
    assert((command.size() % 3) == 0);
    for (size_t dataIndex = 0; dataIndex < command.size(); ) {
      auto event = AUMIDIEvent();
      event.eventSampleTime = AUEventSampleTimeImmediate;
      event.length = 3;
      event.data[0] = command[dataIndex++];
      event.data[1] = command[dataIndex++];
      event.data[2] = command[dataIndex++];
      engine_.doMIDIEvent(event);
    }
  }

  void sendRaw(const std::vector<uint8_t>& command) noexcept {
    auto rawEvent = std::vector<uint8_t>(sizeof(AUMIDIEvent) + command.size(), uint8_t(0));
    AUMIDIEvent& event = *reinterpret_cast<AUMIDIEvent*>(rawEvent.data());
    event.eventSampleTime = AUEventSampleTimeImmediate;
    event.length = command.size();
    ::memcpy(event.data, command.data(), command.size());
    engine_.doMIDIEvent(event);
  }

  void sendNoteOn(uint8_t note, uint8_t velocity = 64) noexcept {
    AUMIDIEvent midiEvent;
    midiEvent.data[0] = SF2::valueOf(SF2::MIDI::CoreEvent::noteOn);
    midiEvent.data[1] = note;
    midiEvent.data[2] = velocity;
    midiEvent.length = 3;
    engine_.doMIDIEvent(midiEvent);
  }

  void sendNoteOff(uint8_t note) noexcept {
    AUMIDIEvent midiEvent;
    midiEvent.data[0] = SF2::valueOf(SF2::MIDI::CoreEvent::noteOff);
    midiEvent.data[1] = note;
    midiEvent.length = 2;
    engine_.doMIDIEvent(midiEvent);
  }

  void sendAllOff() noexcept {
    AUMIDIEvent midiEvent;
    midiEvent.data[0] = SF2::valueOf(SF2::MIDI::CoreEvent::reset);
    midiEvent.length = 1;
    engine_.doMIDIEvent(midiEvent);
  }

  void setParameter(SF2::Render::Engine::Parameters::EngineParameterAddress address, AUValue value) noexcept {
    auto event = AUParameterEvent();
    event.parameterAddress = SF2::valueOf(address);
    event.value = value;
    engine_.doParameterEvent(event, 0);
  }

  void setParameter(SF2::Entity::Generator::Index index, AUValue value) noexcept {
    auto event = AUParameterEvent();
    event.parameterAddress = SF2::valueOf(index);
    event.value = value;
    engine_.doParameterEvent(event, 0);
  }

private:
  Engine engine_;
  AUAudioFrameCount maxFramesToRender_{512};
  AVAudioFormat* format_{nullptr};
  AVAudioPCMBuffer* dryBuffer_{nullptr};
  AVAudioPCMBuffer* chorusBuffer_{nullptr};
  AVAudioPCMBuffer* reverbBuffer_{nullptr};
  AVAudioFrameCount duration_{0};
  DSPHeaders::BusBufferFacet dryFacet_;
  DSPHeaders::BusBufferFacet chorusFacet_;
  DSPHeaders::BusBufferFacet reverbFacet_;
  int renderIndex_{0};
};


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
      voices_.back().configure(presetConfigs_[index]);
    }
  }

  SF2::Float sampleRate() const { return sampleRate_; }
  size_t count() const { return presetConfigs_.size(); }

  void start() {
    for (size_t index = 0; index < presetConfigs_.size(); ++index) {
      voices_[index].start();
    }
  }

  void stop() { for (auto& voice : voices_) voice.stop(); }

  void releaseKey() {
    auto releaseKeyState = SF2::Render::Voice::Voice::ReleaseKeyState{1, false, false};
    for (auto& voice : voices_) voice.releaseKey(releaseKeyState);
  }

  void releaseKey(const SF2::Render::Voice::Voice::ReleaseKeyState& releaseKeyState) {
    for (auto& voice : voices_) voice.releaseKey(releaseKeyState);
  }

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
  inline static SF2::Float epsilonValue() {
    if constexpr (std::is_same_v<SF2::Float, float>) {
      return 1.0e-3;
    } else {
      return 1.0e-12;
    }
  }

  static inline const SF2::Float epsilon = epsilonValue();
  static BOOL playAudioInTests();

  PresetTestContextBase(int urlIndex, SF2::Float sampleRate)
  :
  urlIndex_{urlIndex}, sampleRate_{sampleRate}, presets_{}
  {
    ;
  }

  const SF2::Render::Preset& preset(int presetIndex) const {
    // Lazily create the PresetCollection for the file when first asked for a preset.
    if (presets_.empty()) {
     const_cast<PresetTestContextBase*>(this)->presets_.build(getFile(urlIndex_));
    }
    const auto& p{presets_[presetIndex].configuration()};
    std::cout << "Using preset: " << presetIndex << " " << p.name() << " " << p.bank() << "/" << p.program()
    << " " << getUrl(urlIndex_).path.UTF8String << std::endl;
    return presets_[presetIndex];
  }

  TestVoiceCollection makeVoiceCollection(int presetIndex, int midiNote, int midiVelocity = 64) {
    channelState_.reset();
    return {midiNote, midiVelocity, preset(presetIndex), sampleRate_, channelState_};
  }

  std::vector<TestVoiceCollection> makeVoicesCollection(int presetIndex, const std::vector<int>& midiNotes,
                                                        int midiVelocity = 64) {
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
    auto found{preset(presetIndex).find(midiKey, midiVelocity)};
    return makeState(found[0]);
  }

  const NSURL* url() const { return getUrl(urlIndex_); }
  const std::string path() const { return url().path.UTF8String; }
  SF2::IO::File& file() const { return getFile(urlIndex_); }
  int fd() const { return ::open(path().c_str(), O_RDONLY); }

private:
  static NSURL* getUrl(int urlIndex);
  static SF2::IO::File& getFile(int urlIndex);

  // SF2::Float sampleRate() const { return sampleRate_; }

  int urlIndex_;
  SF2::Render::PresetCollection presets_;
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

struct SF2::Render::Voice::State::State::Tester {
  void setValue(State& state, Index index, int value) { state.setValue(index, value); }
  void setAdjustment(State& state, Index index, int value) { state.setAdjustment(index, value); }
  void addModulator(State& state, const Entity::Modulator::Modulator& mod) { state.addModulator(mod); }
};

@interface SamplePlayingTestCase : XCTestCase <AVAudioPlayerDelegate> {
  SF2::Float epsilon;
  SampleBasedContexts contexts;
  SF2::Render::Voice::State::State::Tester sst;
}

@property (nonatomic, retain) AVAudioPlayer* player;
@property (nonatomic, retain) XCTestExpectation* playedAudioExpectation;
@property (nonatomic, retain) NSURL* audioFileURL;
@property (nonatomic, retain) AVAudioPCMBuffer* buffer;
@property (nonatomic) BOOL deleteFile;
@property (nonatomic) BOOL playAudio;

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
