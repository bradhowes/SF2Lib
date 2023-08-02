// Copyright © 2020 Brad Howes. All rights reserved.

#include <AVFoundation/AVFoundation.h>
#include <iostream>

#include <XCTest/XCTest.h>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.h"
#include "SF2Lib/Render/Engine/Engine.hpp"

using namespace SF2;
using namespace SF2::Render::Engine;

@interface EngineTests : SamplePlayingTestCase
@end

namespace SF2::Render::Engine {
struct EngineTestInjector {
  void testDoMIDIEvent(Engine& engine, const AUMIDIEvent& midiEvent) {
    engine.doMIDIEvent(midiEvent);
  }
  void testChangeProgram(Engine& engine, int program) {
    engine.changeProgram(program);
  }
};
}

static void
renderUntil(Engine& engine, Mixer& mixer, int& frameIndex, int frameCount, int until) {
  while (frameIndex++ < until) {
    engine.renderInto(mixer, frameCount);
    mixer.shiftOver(frameCount);
  }
}

@implementation EngineTests

- (void)testInit {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Generator::Interpolator::linear);
  XCTAssertEqual(engine.voiceCount(), 32);
  XCTAssertEqual(engine.activeVoiceCount(), 0);
}

- (void)testLoad {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Generator::Interpolator::linear);
  XCTAssertFalse(engine.hasActivePreset());
  engine.load(contexts.context0.file(), 0);
  XCTAssertEqual(engine.presetCount(), 235);
  XCTAssertTrue(engine.hasActivePreset());
  engine.load(contexts.context1.file(), 10000);
  XCTAssertFalse(engine.hasActivePreset());
}

- (void)testUsePresetByIndex {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Generator::Interpolator::linear);
  engine.load(contexts.context0.file(), 0);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("Piano 1", engine.activePresetName());
  engine.usePreset(1);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 1", engine.activePresetName());
  engine.usePreset(2);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 1d", engine.activePresetName());
  engine.usePreset(9999);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
}

- (void)testUsePresetByBankProgram {
  Engine engine(44100.0, 32, SF2::Render::Voice::Sample::Generator::Interpolator::linear);
  engine.load(contexts.context0.file(), 0);
  engine.usePreset(0, 0);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("Piano 1", engine.activePresetName());
  engine.usePreset(0, 1);
  XCTAssertTrue(engine.hasActivePreset());
  std::cout << engine.activePresetName() << '\n';
  XCTAssertEqual("Piano 2", engine.activePresetName());
  engine.usePreset(128, 56);
  XCTAssertTrue(engine.hasActivePreset());
  XCTAssertEqual("SFX", engine.activePresetName());
  engine.usePreset(-1, -1);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  engine.usePreset(-1, 0);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  engine.usePreset(0, -1);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  engine.usePreset(129, 0);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
  engine.usePreset(0, 128);
  XCTAssertFalse(engine.hasActivePreset());
  XCTAssertEqual("", engine.activePresetName());
}

- (void)testRolandPianoChordRenderLinear {
  Float sampleRate{48000.0};
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
  DSPHeaders::BufferFacet dryFacet;
  dryFacet.setChannelCount(2);
  dryFacet.assignBufferList(dryBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers dry{dryFacet.busBuffers()};

  AVAudioPCMBuffer* chorusBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  DSPHeaders::BufferFacet chorusFacet;
  chorusFacet.setChannelCount(2);
  chorusFacet.assignBufferList(chorusBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers chorus{chorusFacet.busBuffers()};

  AVAudioPCMBuffer* reverbBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  DSPHeaders::BufferFacet reverbFacet;
  reverbFacet.setChannelCount(2);
  reverbFacet.assignBufferList(reverbBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers reverb{reverbFacet.busBuffers()};

  Mixer mixer{dry, chorus, reverb};

  XCTAssertEqual(0, engine.activeVoiceCount());

  int frameIndex = 0;
  auto playChord = [&](int note1, int note2, int note3, bool sustain) {
    renderUntil(engine, mixer, frameIndex, frameCount, noteOnFrame);
    engine.noteOn(note1, 64);
    engine.noteOn(note2, 64);
    engine.noteOn(note3, 64);
    renderUntil(engine, mixer, frameIndex, frameCount, noteOffFrame);
    if (!sustain) {
      engine.noteOff(note1);
      engine.noteOff(note2);
      engine.noteOff(note3);
    }
    noteOnFrame += noteOnDuration;
    noteOffFrame += noteOnDuration;
  };

  playChord(60, 64, 67, false);
  playChord(60, 65, 69, false);
  playChord(60, 64, 67, false);
  playChord(59, 62, 67, false);
  playChord(60, 64, 67, true);

  renderUntil(engine, mixer, frameIndex, frameCount, frames);
  if (remaining > 0) engine.renderInto(mixer, remaining);

  XCTAssertEqual(0, engine.activeVoiceCount());

  [self playSamples: dryBuffer count: sampleCount];
}

- (void)testRolandPianoChordRenderCubic4thOrder {
  Float sampleRate{48000.0};
  AUAudioFrameCount frameCount{512};
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  Engine engine(sampleRate, 6, SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder);
  engine.load(contexts.context2.file(), 0);
  engine.setRenderingFormat(3, format, frameCount);

  // Set NPRN state so that voices send 20% output to the chorus channel
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, 120);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Entity::Generator::Index::chorusEffectSend));
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 65);

  int cycles = 5;
  int seconds = 4.0;
  int sampleCount = sampleRate * seconds * cycles;
  int frames = sampleCount / frameCount;
  int remaining = sampleCount - frames * frameCount;
  int noteOnFrame = 10;
  int noteOnDuration = 50;
  int noteOffFrame = noteOnFrame + noteOnDuration;

  AVAudioPCMBuffer* dryBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  DSPHeaders::BufferFacet dryFacet;
  dryFacet.setChannelCount(2);
  dryFacet.assignBufferList(dryBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers dry{dryFacet.busBuffers()};

  AVAudioPCMBuffer* chorusBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  DSPHeaders::BufferFacet chorusFacet;
  chorusFacet.setChannelCount(2);
  chorusFacet.assignBufferList(chorusBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers chorus{chorusFacet.busBuffers()};

  AVAudioPCMBuffer* reverbBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  DSPHeaders::BufferFacet reverbFacet;
  reverbFacet.setChannelCount(2);
  reverbFacet.assignBufferList(reverbBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers reverb{reverbFacet.busBuffers()};

  Mixer mixer{dry, chorus, reverb};

  XCTAssertEqual(0, engine.activeVoiceCount());

  int frameIndex = 0;
  auto playChord = [&](int note1, int note2, int note3, bool sustain) {
    renderUntil(engine, mixer, frameIndex, frameCount, noteOnFrame);
    engine.noteOn(note1, 64);
    engine.noteOn(note2, 64);
    engine.noteOn(note3, 64);
    renderUntil(engine, mixer, frameIndex, frameCount, noteOffFrame);
    if (!sustain) {
      engine.noteOff(note1);
      engine.noteOff(note2);
      engine.noteOff(note3);
    }
    noteOnFrame += noteOnDuration;
    noteOffFrame += noteOnDuration;
  };

  for (auto count = 0; count < cycles; ++count) {
    playChord(60, 64, 67, false);
    playChord(60, 65, 69, false);
    playChord(60, 64, 67, false);
    playChord(59, 62, 67, false);
    playChord(60, 64, 67, count == cycles - 1);
  }

  XCTAssertEqual(6, engine.activeVoiceCount());

  renderUntil(engine, mixer, frameIndex, frameCount, frames);
  if (remaining > 0) engine.renderInto(mixer, remaining);

  XCTAssertEqual(0, engine.activeVoiceCount());

  [self playSamples: dryBuffer count: sampleCount];
  // [self playSamples: chorusBuffer count: sampleCount];
}

//- (void)testDoMIDIEvent {
//  Float sampleRate{48000.0};
//  AUAudioFrameCount frameCount = 512;
//  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];
//  Engine engine(sampleRate, 6, SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder);
//  engine.load(contexts.context0.file(), 1);
//  NSString* name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
//  NSLog(@"name: |%@|", name);
//  XCTAssertTrue([name isEqualToString:@"Piano 1"]);
//
//  const NSURL* other = contexts.context1.url();
//
//  NSMutableData* data = [[NSMutableData alloc] initWithLength:
//
//  AUMIDIEvent mi;
//
//}

- (void)testChangeProgram {
  Float sampleRate{48000.0};
  AUAudioFrameCount frameCount = 512;
  Engine engine(sampleRate, 6, SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder);
  engine.load(contexts.context0.file(), 1);
  NSString* name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
  NSLog(@"name: |%@|", name);
  XCTAssertTrue([name isEqualToString:@"Piano 1"]);
  EngineTestInjector eti;
  eti.testChangeProgram(engine, 2);
  name = [NSString stringWithCString:engine.activePresetName().c_str() encoding:NSUTF8StringEncoding];
  NSLog(@"name: |%@|", name);
  XCTAssertTrue([name isEqualToString:@"Piano 3"]);
}

- (void)testYamahaPianoChordRender {
  Float sampleRate{48000.0};
  AUAudioFrameCount frameCount = 512;
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  Engine engine(sampleRate, 6, SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder);
  engine.load(contexts.context0.file(), 0);
  engine.setRenderingFormat(3, format, frameCount);

  // Set NPRN state so that voices send 20% output to the chorus channel
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnMSB, 120);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Entity::Generator::Index::chorusEffectSend));
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
  engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 65);

  int seconds = 6;
  int sampleCount = sampleRate * seconds;
  int frames = sampleCount / frameCount;
  int remaining = sampleCount - frames * frameCount;
  int noteOnFrame = 10;
  int noteOnDuration = 50;
  int noteOffFrame = noteOnFrame + noteOnDuration;

  AVAudioPCMBuffer* dryBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  DSPHeaders::BufferFacet dryFacet;
  dryFacet.setChannelCount(2);
  dryFacet.assignBufferList(dryBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers dry{dryFacet.busBuffers()};

  AVAudioPCMBuffer* chorusBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  DSPHeaders::BufferFacet chorusFacet;
  chorusFacet.setChannelCount(2);
  chorusFacet.assignBufferList(chorusBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers chorus{chorusFacet.busBuffers()};

  AVAudioPCMBuffer* reverbBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
  DSPHeaders::BufferFacet reverbFacet;
  reverbFacet.setChannelCount(2);
  reverbFacet.assignBufferList(reverbBuffer.mutableAudioBufferList);
  DSPHeaders::BusBuffers reverb{reverbFacet.busBuffers()};

  Mixer mixer{dry, chorus, reverb};

  XCTAssertEqual(0, engine.activeVoiceCount());

  int frameIndex = 0;
  int velocity = 127;
  auto playChord = [&](int note1, int note2, int note3, bool sustain) {
    renderUntil(engine, mixer, frameIndex, frameCount, noteOnFrame);
    engine.noteOn(note1, velocity);
    engine.noteOn(note2, velocity);
    engine.noteOn(note3, velocity);
    velocity -= 16;
    renderUntil(engine, mixer, frameIndex, frameCount, noteOffFrame);
    if (!sustain) {
      engine.noteOff(note1);
      engine.noteOff(note2);
      engine.noteOff(note3);
    }
    noteOnFrame += noteOnDuration;
    noteOffFrame += noteOnDuration;
  };

  playChord(60, 64, 67, false);
  playChord(60, 65, 69, false);
  playChord(60, 64, 67, false);
  playChord(59, 62, 67, false);
  playChord(60, 64, 67, true);

  renderUntil(engine, mixer, frameIndex, frameCount, frames);
  if (remaining > 0) engine.renderInto(mixer, remaining);

  XCTAssertEqual(3, engine.activeVoiceCount());

  [self playSamples: dryBuffer count: sampleCount];
}

// Render 1 second of audio at 48000.0 sample rate using all voices of an engine and interpolating using 4th-order cubic.
// Uses both effects buffers to account for mixing effort when they are active.
- (void)testEngineRenderPerformanceUsingCubic4thOrder
{
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    Float sampleRate{48000.0};
    AUAudioFrameCount samplesPerFrame = 512;
    AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

    Engine engine(sampleRate, 64, SF2::Render::Voice::Sample::Generator::Interpolator::cubic4thOrder);
    engine.load(contexts.context2.file(), 0);
    engine.setRenderingFormat(3, format, samplesPerFrame);

    // Set NPRN state so that voices send 20% output to the chorus channel
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnMSB, 120);
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Entity::Generator::Index::chorusEffectSend));
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 65);

    // Set NPRN state so that voices send 10% output to the reverb channel
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnMSB, 120);
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Entity::Generator::Index::reverbEffectSend));
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 100);
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 64);

    int seconds = 1;
    int sampleCount = sampleRate * seconds;
    int frames = sampleCount / samplesPerFrame;
    int remaining = sampleCount - frames * samplesPerFrame;

    AVAudioPCMBuffer* dryBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
    DSPHeaders::BufferFacet dryFacet;
    dryFacet.setChannelCount(2);
    dryFacet.assignBufferList(dryBuffer.mutableAudioBufferList);
    DSPHeaders::BusBuffers dry{dryFacet.busBuffers()};

    AVAudioPCMBuffer* chorusBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
    DSPHeaders::BufferFacet chorusFacet;
    chorusFacet.setChannelCount(2);
    chorusFacet.assignBufferList(chorusBuffer.mutableAudioBufferList);
    DSPHeaders::BusBuffers chorus{chorusFacet.busBuffers()};

    AVAudioPCMBuffer* reverbBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
    DSPHeaders::BufferFacet reverbFacet;
    reverbFacet.setChannelCount(2);
    reverbFacet.assignBufferList(reverbBuffer.mutableAudioBufferList);
    DSPHeaders::BusBuffers reverb{reverbFacet.busBuffers()};

    Mixer mixer{dry, chorus, reverb};

    for (int voice = 0; voice < engine.voiceCount(); ++voice) {
      engine.noteOn(32 + 2 * voice, 64);
    }

    [self startMeasuring];
    for (auto frameIndex = 0; frameIndex < frames; ++frameIndex) {
      engine.renderInto(mixer, samplesPerFrame);
    }
    if (remaining > 0) engine.renderInto(mixer, remaining);
    [self stopMeasuring];
  }];
}

// Render 1 second of audio at 48000.0 sample rate using all voices of an engine and interpolating using linear
// algorithm. Uses both effects buffers to account for mixing effort when they are active.
- (void)testEngineRenderPerformanceUsingLinearInterpolation
{
  NSArray* metrics = @[XCTPerformanceMetric_WallClockTime];
  [self measureMetrics:metrics automaticallyStartMeasuring:NO forBlock:^{
    Float sampleRate{48000.0};
    AUAudioFrameCount samplesPerFrame = 512;
    AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

    Engine engine(sampleRate, 64, SF2::Render::Voice::Sample::Generator::Interpolator::linear);
    engine.load(contexts.context2.file(), 0);
    engine.setRenderingFormat(3, format, samplesPerFrame);

    // Set NPRN state so that voices send 20% output to the chorus channel
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnMSB, 120);
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Entity::Generator::Index::chorusEffectSend));
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 72);
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 65);

    // Set NPRN state so that voices send 10% output to the reverb channel
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnMSB, 120);
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::nrpnLSB, int(Entity::Generator::Index::reverbEffectSend));
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryLSB, 100);
    engine.channelState().setContinuousControllerValue(MIDI::ControlChange::dataEntryMSB, 64);

    int seconds = 1;
    int sampleCount = sampleRate * seconds;
    int frames = sampleCount / samplesPerFrame;
    int remaining = sampleCount - frames * samplesPerFrame;

    AVAudioPCMBuffer* dryBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
    DSPHeaders::BufferFacet dryFacet;
    dryFacet.setChannelCount(2);
    dryFacet.assignBufferList(dryBuffer.mutableAudioBufferList);
    DSPHeaders::BusBuffers dry{dryFacet.busBuffers()};

    AVAudioPCMBuffer* chorusBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
    DSPHeaders::BufferFacet chorusFacet;
    chorusFacet.setChannelCount(2);
    chorusFacet.assignBufferList(chorusBuffer.mutableAudioBufferList);
    DSPHeaders::BusBuffers chorus{chorusFacet.busBuffers()};

    AVAudioPCMBuffer* reverbBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:sampleCount];
    DSPHeaders::BufferFacet reverbFacet;
    reverbFacet.setChannelCount(2);
    reverbFacet.assignBufferList(reverbBuffer.mutableAudioBufferList);
    DSPHeaders::BusBuffers reverb{reverbFacet.busBuffers()};

    Mixer mixer{dry, chorus, reverb};

    for (int voice = 0; voice < engine.voiceCount(); ++voice) {
      engine.noteOn(32 + 2 * voice, 64);
    }

    [self startMeasuring];
    for (auto frameIndex = 0; frameIndex < frames; ++frameIndex) {
      engine.renderInto(mixer, samplesPerFrame);
    }
    if (remaining > 0) engine.renderInto(mixer, remaining);
    [self stopMeasuring];
  }];
}

@end
