// Copyright © 2022 Brad Howes. All rights reserved.
//

#pragma once

#include <iomanip>
#include <AVFoundation/AVFoundation.h>
#include <XCTest/XCTest.h>

#include "DSPHeaders/BusBufferFacet.hpp"
#include "DSPHeaders/Types.hpp"

#include "SF2File/IO/File.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/Render/Engine/LiveGeneratorParameters.hpp"
#include "SF2Lib/Render/Engine/Mixer.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"
#include "SF2Lib/Render/Preset.hpp"
#include "SF2Lib/Render/Voice/State/State.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

struct TestEngineHarness {
  using Engine = SF2::Render::Engine::Engine;
  using Mixer = SF2::Render::Engine::Mixer;
  using Interpolator = SF2::Render::Voice::Sample::Interpolator;

  explicit TestEngineHarness(SF2::Float sampleRate, size_t voiceCount = SF2::Render::Engine::traits::maxVoiceCount,
                             Interpolator interpolator = Interpolator::cubic4thOrder) noexcept :
  engine_{sampleRate, voiceCount, interpolator, -1.0}
  {
    format_ = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];
    engine_.setRenderingFormat(3, format_, 512);
    engine_.makeTree();
  }

  Mixer createMixer(double seconds) noexcept
  {
    bufferDuration_ = seconds;
    bufferFrameCount_ = AVAudioFrameCount(ceil(seconds * engine_.sampleRate()));
    bufferFrameIndex_ = 0;
    dryBuffer_ = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format_ frameCapacity:bufferFrameCount_];
    dryFacet_.setChannelCount(2);
    dryFacet_.assignBufferList(dryBuffer_.mutableAudioBufferList);
    DSPHeaders::BusBuffers dry{dryFacet_.busBuffers()};

    chorusBuffer_ = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format_ frameCapacity:bufferFrameCount_];
    chorusFacet_.setChannelCount(2);
    chorusFacet_.assignBufferList(chorusBuffer_.mutableAudioBufferList);
    DSPHeaders::BusBuffers chorus{chorusFacet_.busBuffers()};

    reverbBuffer_ = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format_ frameCapacity:bufferFrameCount_];
    reverbFacet_.setChannelCount(2);
    reverbFacet_.assignBufferList(reverbBuffer_.mutableAudioBufferList);
    DSPHeaders::BusBuffers reverb{reverbFacet_.busBuffers()};

    return Mixer(dry, chorus, reverb);
  }

  void renderMaxFramesCount(Mixer& mixer, AVAudioFrameCount count = 1) noexcept {
    renderForCount(mixer, count * maxFramesToRender_);
  }

  void renderForCount(Mixer& mixer, AVAudioFrameCount count) noexcept {
    if (bufferFrameIndex_ < bufferFrameCount_) {
      auto amount = std::min(bufferFrameCount_ - bufferFrameIndex_, count);
      if (amount > 0) {
        engine_.renderInto(mixer, amount);
        mixer.shiftOver(amount);
        bufferFrameIndex_ += amount;
      }
    }
  }

  void renderForDuration(Mixer& mixer, double duration) noexcept {
    auto amount = AVAudioFrameCount(duration * engine_.sampleRate());
    renderForCount(mixer, amount);
  }

  void renderToEnd(Mixer& mixer) noexcept {
    if (bufferFrameIndex_ < bufferFrameCount_) {
      renderForCount(mixer, bufferFrameCount_ - bufferFrameIndex_);
    }
  }

  Engine& engine() noexcept { return engine_; }

  /**
   Turn on the render time budget (the harness normally runs without one) and use the given clock for it.

   @param scaling the fraction of the real-time duration of a render slice that rendering may use
   @param clock the time source, in nanoseconds
   */
  void enableRenderingBudget(double scaling, Engine::Clock clock) noexcept {
    engine_.renderingTimeBudgetScaling_ = scaling;
    engine_.clock_ = clock;
  }

  /// Turn the render time budget off again.
  void disableRenderingBudget() noexcept { engine_.renderingTimeBudgetScaling_ = -1.0; }

  /// @returns the engine's running average of the nanoseconds it takes to render one voice for one frame
  double averageVoiceFrameNanoseconds() const noexcept { return engine_.averageVoiceFrameNanoseconds_; }

  /// Set the engine's running average of the nanoseconds it takes to render one voice for one frame
  void setAverageVoiceFrameNanoseconds(double value) noexcept { engine_.averageVoiceFrameNanoseconds_ = value; }

  /// @returns the nanoseconds of real time in one frame at the engine's sample rate
  uint64_t frameNanoseconds() const noexcept { return engine_.renderingTimeBudgetIntervalNanoseconds_; }

  /// @returns the voice with the given index
  SF2::Render::Voice::Voice& voice(size_t index) noexcept { return engine_.voices_[index]; }

  SF2::IO::File::LoadResponse load(const std::string& path, size_t index) {
    return engine_.loadFileAndPreset(path, index);
  }

  typedef void (^ WorkItemBlock)();

  void postWorkItem(WorkItemBlock block) { dispatch_async(engine_.workQueue_, block); }

  /// Block until every work item queued so far has run. MIDI program changes load on the work queue, so call this
  /// after one before checking the active preset or sending notes (they are ignored while a change is pending).
  void drainWorkQueue() { dispatch_sync(engine_.workQueue_, ^{ }); }

  /// Hold back work-queue items, so a test can look at the engine while a program change or SysEx load is pending.
  void suspendWorkQueue() { dispatch_suspend(engine_.workQueue_); }

  /// Let held-back work-queue items run again.
  void resumeWorkQueue() { dispatch_resume(engine_.workQueue_); }

  /// @returns number of replaced presets states that have not been freed yet
  size_t retiredPresetsStateCount() {
    std::lock_guard<std::mutex> lock(engine_.retiredMutex_);
    return engine_.retired_.size();
  }

  void usePresetWithIndex(size_t index) { engine_.loadFileAndPreset("", index); }

  AVAudioFrameCount maxFramesToRender() const noexcept { return maxFramesToRender_; }
  AVAudioFrameCount bufferFrameCount() const noexcept { return bufferFrameCount_; }
  AVAudioFrameCount bufferFrameIndex() const noexcept { return bufferFrameIndex_; }

  AVAudioPCMBuffer* dryBuffer() const noexcept { return dryBuffer_; }
  AVAudioPCMBuffer* chorusBuffer() const noexcept { return chorusBuffer_; }
  AVAudioPCMBuffer* reverbBuffer() const noexcept { return reverbBuffer_; }

  double duration() const noexcept { return bufferDuration_; }

  AUValue lastDrySample() noexcept { return dryFacet_.busBuffers()[0][-1]; }
  AUValue lastChorusSample() noexcept { return chorusFacet_.busBuffers()[0][-1]; }
  AUValue lastReverbSample() noexcept { return reverbFacet_.busBuffers()[0][-1]; }

  AUValue lastDrySample(size_t channel) noexcept { return dryFacet_.busBuffers()[channel][-1]; }
  AUValue lastChorusSample(size_t channel) noexcept { return chorusFacet_.busBuffers()[channel][-1]; }
  AUValue lastReverbSample(size_t channel) noexcept { return reverbFacet_.busBuffers()[channel][-1]; }

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
    event.length = uint16_t(command.size());
    ::memcpy(event.data, command.data(), command.size());
    engine_.doMIDIEvent(event);
  }

  void sendNoteOn(uint8_t note, uint8_t velocity = 64) noexcept {
    AUMIDIEvent midiEvent;
    midiEvent.data[0] = DSPHeaders::valueOf(SF2::MIDI::CoreEvent::noteOn);
    midiEvent.data[1] = note;
    midiEvent.data[2] = velocity;
    midiEvent.length = 3;
    engine_.doMIDIEvent(midiEvent);
  }

  void sendNoteOff(uint8_t note) noexcept {
    AUMIDIEvent midiEvent;
    midiEvent.data[0] = DSPHeaders::valueOf(SF2::MIDI::CoreEvent::noteOff);
    midiEvent.data[1] = note;
    midiEvent.length = 2;
    engine_.doMIDIEvent(midiEvent);
  }

  void sendAllOff() noexcept {
    AUMIDIEvent midiEvent;
    midiEvent.data[0] = DSPHeaders::valueOf(SF2::MIDI::CoreEvent::reset);
    midiEvent.length = 1;
    engine_.doMIDIEvent(midiEvent);
  }

  void setParameter(SF2::Render::Engine::ParameterAddress address, AUValue value) noexcept {
    auto event = AUParameterEvent();
    event.parameterAddress = DSPHeaders::valueOf(address);
    event.value = value;
    engine_.doParameterEvent(event, 0);
  }

  void setParameter(SF2::Entity::Generator::Index index, AUValue value) noexcept {
    auto event = AUParameterEvent();
    event.parameterAddress = DSPHeaders::valueOf(index);
    event.value = value;
    engine_.doParameterEvent(event, 0);
  }

private:
  Engine engine_;
  double bufferDuration_;

  AUAudioFrameCount maxFramesToRender_{512};
  AVAudioFrameCount bufferFrameCount_{0};
  AVAudioFrameCount bufferFrameIndex_{0};

  AVAudioFormat* format_{nullptr};
  AVAudioPCMBuffer* dryBuffer_{nullptr};
  AVAudioPCMBuffer* chorusBuffer_{nullptr};
  AVAudioPCMBuffer* reverbBuffer_{nullptr};

  DSPHeaders::BusBufferFacet dryFacet_;
  DSPHeaders::BusBufferFacet chorusFacet_;
  DSPHeaders::BusBufferFacet reverbFacet_;
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
      voices_.emplace_back();
      voices_.back().initialize(index, sampleRate_);
      voices_.back().configure(presetConfigs_[index], channelState_);
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
    auto releaseKeyState = SF2::Render::Voice::Voice::ReleaseKeyState{1, {false, false}};
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
  static SF2::Float epsilonValue() {
    if constexpr (std::is_same_v<SF2::Float, float>) {
      return 1.0e-6;
    } else {
      return 1.0e-12;
    }
  }

  static inline const SF2::Float epsilon = epsilonValue();
  static BOOL playAudioInTests();

  PresetTestContextBase(size_t urlIndex, SF2::Float sampleRate)
  :
  urlIndex_{urlIndex}, presets_{}, sampleRate_{sampleRate}
  {
    ;
  }

  const SF2::Render::Preset& preset(size_t presetIndex) {
    // Lazily create the PresetCollection for the file when first asked for a preset.
    if (presets_.empty()) {
     const_cast<PresetTestContextBase*>(this)->presets_.build(getFile(urlIndex_));
    }
    presets_[presetIndex].loadSamples(getFile(urlIndex_));
    return presets_[presetIndex];
  }

  TestVoiceCollection makeVoiceCollection(size_t presetIndex, int midiNote, int midiVelocity = 64) {
    channelState_.reset();
    return {midiNote, midiVelocity, preset(presetIndex), sampleRate_, channelState_};
  }

  std::vector<TestVoiceCollection> makeVoicesCollection(size_t presetIndex, const std::vector<int>& midiNotes,
                                                        int midiVelocity = 64) {
    std::vector<TestVoiceCollection> notes;
    for (auto midiNote : midiNotes) {
      notes.emplace_back(makeVoiceCollection(presetIndex, midiNote, midiVelocity));
    }
    return notes;
  }

  SF2::Render::Voice::State::State makeState(const SF2::Render::Voice::State::Config& config) const {
    SF2::Render::Voice::State::State state(sampleRate_);
    state.prepareForVoice(config, channelState_);
    return state;
  }

  SF2::Render::Voice::State::State makeState(size_t presetIndex, int midiKey, int midiVelocity) {
    auto found{preset(presetIndex).find(midiKey, midiVelocity)};
    return makeState(found[0]);
  }

  const NSURL* url() const { return getUrl(urlIndex_); }
  const std::string path() const {
    auto nsPath = url().path;
    const char* utf8Str = nsPath.UTF8String;
    return utf8Str ? std::string(utf8Str) : std::string();
  }
  SF2::IO::File& file() const { return getFile(urlIndex_); }
  int fd() const { return ::open(path().c_str(), O_RDONLY); }
  SF2::MIDI::ChannelState& channelState() { return channelState_; }

private:
  static NSURL* getUrl(size_t urlIndex);
  static SF2::IO::File& getFile(size_t urlIndex);

  // SF2::Float sampleRate() const { return sampleRate_; }

  size_t urlIndex_;
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

@interface SamplePlayingTestCase : XCTestCase <AVAudioPlayerDelegate>

@property (nonatomic) SF2::Render::Voice::State::State::Tester sst;
@property (nonatomic) SampleBasedContexts* contexts;
@property (nonatomic, retain) AVAudioPlayer* player;
@property (nonatomic, retain) XCTestExpectation* playedAudioExpectation;
@property (nonatomic, retain) NSURL* audioFileURL;
@property (nonatomic, retain) AVAudioPCMBuffer* samplesBuffer;
@property (nonatomic) BOOL deleteFile;
@property (nonatomic) BOOL playAudio;
@property (nonatomic) SF2::Float epsilon;

- (void)playSamples:(AVAudioPCMBuffer*)buffer count:(AVAudioFrameCount)sampleCount;

- (AVAudioPCMBuffer*)allocateBufferFor:(const TestVoiceCollection&)voices capacity:(AVAudioFrameCount)sampleCount;
- (AVAudioPCMBuffer*)allocateBuffer:(SF2::Float)sampleRate numberOfChannels:(AVAudioChannelCount)channels capacity:(AVAudioFrameCount)sampleCount;

- (size_t)renderInto:(AVAudioPCMBuffer*)buffer mono:(SF2::Render::Voice::Voice&)left forCount:(AVAudioFrameCount)sampleCount startingAt:(size_t)offset;
- (size_t)renderInto:(AVAudioPCMBuffer*)buffer left:(SF2::Render::Voice::Voice&)left right:(SF2::Render::Voice::Voice&)right forCount:(AVAudioFrameCount)sampleCount startingAt:(size_t)offset;
- (size_t)renderInto:(AVAudioPCMBuffer*)buffer voices:(TestVoiceCollection&)voices forCount:(AVAudioFrameCount)sampleCount startingAt:(size_t)offset;
- (size_t)renderInto:(AVAudioPCMBuffer*)buffer voices:(TestVoiceCollection&)voices forCount:(AVAudioFrameCount)sampleCount startingAt:(size_t)offset afterRenderSample:(void (^)(size_t))block;

- (void)dumpPresets:(const SF2::IO::File&)file;
- (void)dumpSamples:(const std::vector<AUValue>&)samples;

@end

@interface AVAudioPCMBuffer(Accessors)

- (AUValue*)left;
- (AUValue*)right;
- (AUValue*)channel:(size_t)index;
- (void)normalize:(size_t)voiceCount;

@end
