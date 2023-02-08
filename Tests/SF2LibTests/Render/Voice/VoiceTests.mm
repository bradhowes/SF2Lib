// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Types.hpp"

static SF2::Float epsilon = 1.0e-8;

#include <AVFoundation/AVFoundation.h>
#include <iostream>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Configuration.h"
#include "SF2Lib/Render/Preset.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

using namespace SF2;
using namespace SF2::Render;

@interface VoiceTests : SamplePlayingTestCase
@end

@implementation VoiceTests

- (void)setUp {
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputRolandPiano {
  SF2::Float sampleRate = contexts.context2.sampleRate();
  const auto& file = contexts.context2.file();

  MIDI::ChannelState channelState;
  MIDI::NRPN nrpn{channelState};
  InstrumentCollection instruments(file);
  Preset preset(file, instruments, file.presets()[0]);

  // Locate preset to play A4 (69) at full velocity
  auto found = preset.find(69, 127);
  XCTAssertEqual(found.size(), 2);

  // Assign two voices to play the L/R channels
  Voice::Voice v1L{sampleRate, channelState, 0};
  Voice::Voice v1R{sampleRate, channelState, 1};

  int seconds = 1;
  int repetitions = 5;
  int sampleCount = sampleRate * seconds;

  AVAudioPCMBuffer* buffer = [self allocateBuffer:sampleRate numberOfChannels:2 capacity:sampleCount];
  size_t voiceSampleCount{size_t(sampleCount / repetitions)};
  size_t keyReleaseCount{size_t(voiceSampleCount * 0.8)};

  std::vector<AUValue> samples;
  for (auto iteration = 0; iteration < repetitions; ++iteration) {
    v1L.start(found[0], nrpn);
    v1R.start(found[1], nrpn);
    auto start = iteration * voiceSampleCount;
    auto offset = [self renderInto:buffer left:v1L right:v1R forCount: keyReleaseCount startingAt: start];
    samples.push_back([buffer left][start]);
    v1L.releaseKey();
    v1R.releaseKey();
    auto end = [self renderInto:buffer left:v1L right:v1R forCount: voiceSampleCount - keyReleaseCount startingAt: offset];
    samples.push_back([buffer left][offset]);
    samples.push_back([buffer left][end - 1]);
  }

  [self dumpSamples: samples];

  XCTAssertEqual(repetitions * 3, samples.size());

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
    for (auto index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy( 0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy( 0.132379963994, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy( -0.191177546978, samples[index], epsilon); break;
      }
    }
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testVoiceRepeatedRenderGeneratesSameOutputChimes {
  SF2::Float sampleRate = contexts.context0.sampleRate();
  const auto& file = contexts.context0.file();

  MIDI::ChannelState channelState;
  MIDI::NRPN nrpn{channelState};
  InstrumentCollection instruments(file);

  [self dumpPresets:file];

  Preset preset(file, instruments, file.presets()[205]);

  // Locate preset to play A3 (57) at full velocity - it is mono
  auto found = preset.find(57, 127);
  XCTAssertEqual(found.size(), 1);

  Voice::Voice v1{sampleRate, channelState, 0, Voice::Sample::Generator::Interpolator::cubic4thOrder};

  int seconds = 5;
  int repetitions = 5;
  int sampleCount = sampleRate * seconds;

  AVAudioPCMBuffer* buffer = [self allocateBuffer:sampleRate numberOfChannels:1 capacity:sampleCount];
  size_t voiceSampleCount{size_t(sampleCount / repetitions)};
  size_t keyReleaseCount{size_t(voiceSampleCount * 0.95)};

  std::vector<AUValue> samples;

  for (auto iteration = 0; iteration < repetitions; ++iteration) {
    v1.start(found[0], nrpn);
    auto start = iteration * voiceSampleCount;
    auto offset = [self renderInto:buffer mono:v1 forCount: keyReleaseCount startingAt: start];
    samples.push_back([buffer left][start]);
    v1.releaseKey();
    auto end = [self renderInto:buffer mono:v1 forCount: voiceSampleCount - keyReleaseCount startingAt: offset];
    samples.push_back([buffer left][offset]);
    samples.push_back([buffer left][end - 1]);
  }

  [self dumpSamples: samples];

  XCTAssertEqual(repetitions * 3, samples.size());

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
    for (auto index = 0; index < samples.size(); ++index) {
      switch (index % 3) {
        case 0: XCTAssertEqualWithAccuracy( 0.0000000000, samples[index], epsilon); break;
        case 1: XCTAssertEqualWithAccuracy( 0.0498192124069, samples[index], epsilon); break;
        case 2: XCTAssertEqualWithAccuracy( -0.00602600350976, samples[index], epsilon); break;
      }
    }
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testRolandPianoRender {
  SF2::Float sampleRate = contexts.context2.sampleRate();
  const auto& file = contexts.context2.file();

  MIDI::ChannelState channelState;
  MIDI::NRPN nrpn{channelState};
  InstrumentCollection instruments(file);
  Preset preset(file, instruments, file.presets()[0]);

  std::vector<Voice::Voice> voices;
  voices.reserve(6);

  // Play A Maj chord notes
  for (auto note : {69, 73, 76}) {
    auto found = preset.find(note, 127);
    XCTAssertEqual(found.size(), 2);
    // Assign two voices to play the L/R channels
    for (auto index = 0; index < found.size(); ++index) {
      voices.emplace_back(sampleRate, channelState, index);
      voices.back().start(found[index], nrpn);
      XCTAssertTrue(voices.back().isActive());
    }
  }

  XCTAssertEqual(voices.size(), 6);
  for (const auto& voice : voices) {
    XCTAssertTrue(voice.isActive());
  }

  int seconds = 1;
  int sampleCount = sampleRate * seconds;
  AVAudioPCMBuffer* buffer = [self allocateBuffer:sampleRate numberOfChannels:2 capacity:sampleCount];

  // Each voice renders for 1/3 of a second
  size_t voiceSampleCount{size_t(sampleCount / 3)};
  // Release the key after 80% of the voice duration
  size_t keyReleaseCount{size_t(voiceSampleCount * 0.95)};

  std::vector<AUValue> samples;

  size_t offset = 0;
  for (auto index = 0; index < voices.size(); index += 2) {
    auto& vL = voices[index];
    auto& vR = voices[index + 1];
    auto start = (index / 2) * voiceSampleCount;
    auto offset = [self renderInto:buffer left:vL right:vR forCount:keyReleaseCount startingAt:start];
    samples.push_back([buffer left][start]);
    vL.releaseKey();
    vR.releaseKey();
    auto end = [self renderInto:buffer left:vL right:vR forCount:voiceSampleCount - keyReleaseCount startingAt:offset];
    samples.push_back([buffer left][offset]);
    samples.push_back([buffer left][end - 1]);
  }

  [self dumpSamples:samples];
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
    XCTAssertEqualWithAccuracy( 0.0, samples[0], epsilon);
    XCTAssertEqualWithAccuracy( 0.113824002445, samples[1], epsilon);
    XCTAssertEqualWithAccuracy( 0.133370578289, samples[2], epsilon);
    XCTAssertEqualWithAccuracy( 0.0, samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.0180801860988, samples[4], epsilon);
    XCTAssertEqualWithAccuracy( 0.0763034075499, samples[5], epsilon);
    XCTAssertEqualWithAccuracy( 0.0, samples[6], epsilon);
    XCTAssertEqualWithAccuracy( 0.0206023547798, samples[7], epsilon);
    XCTAssertEqualWithAccuracy( 0.0248804222792, samples[8], epsilon);
  }

  [self playSamples: buffer count: sampleCount];
}

- (void)testOrganRender {
  SF2::Float sampleRate = contexts.context0.sampleRate();
  const auto& file = contexts.context0.file();

  MIDI::ChannelState channelState;
  MIDI::NRPN nrpn{channelState};
  InstrumentCollection instruments(file);
  Preset preset(file, instruments, file.presets()[40]);

  std::vector<Voice::Voice> voices;
  voices.reserve(3);

  // Play C Maj chord
  for (auto note : {64, 78, 71}) {
    auto found = preset.find(note, 127);
    XCTAssertEqual(found.size(), 1);
    // Assign two voices to play the L/R channels
    for (auto index = 0; index < found.size(); ++index) {
      voices.emplace_back(sampleRate, channelState, index);
      voices.back().start(found[index], nrpn);
    }
  }

  int seconds = 3;
  int sampleCount = sampleRate * seconds;
  AVAudioPCMBuffer* buffer = [self allocateBuffer:sampleRate numberOfChannels:1 capacity:sampleCount];

  size_t keyDownCount = sampleCount * 0.95;

  for (auto& voice : voices) {
    [self renderInto:buffer mono:voice forCount:keyDownCount startingAt:0];
    voice.releaseKey();
    [self renderInto:buffer mono:voice forCount:sampleCount - keyDownCount startingAt:keyDownCount];
  }

  [buffer normalize:voices.size()];

  auto samples = [buffer left];

  std::cout << std::setprecision(12);
  std::cout << 0 << ' ' << samples[0] << '\n';
  std::cout << 0 << ' ' << samples[keyDownCount] << '\n';
  std::cout << 0 << ' ' << samples[keyDownCount + 1] << '\n';
  std::cout << 0 << ' ' << samples[sampleCount - 1] << '\n';

  XCTAssertEqualWithAccuracy(0.0, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(-0.0135407252237, samples[keyDownCount], epsilon);
  XCTAssertEqualWithAccuracy(-0.0138820651919, samples[keyDownCount + 1], epsilon);
  XCTAssertEqualWithAccuracy(0.0, samples[sampleCount - 1], epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRender {
  const auto& file = contexts.context0.file();
  MIDI::ChannelState channelState;
  MIDI::NRPN nrpn{channelState};
  InstrumentCollection instruments(file);
  Preset preset(file, instruments, file.presets()[80]);
  std::cout << preset.name() << ' ' << preset.bank() << '/' << preset.program() << '\n';

  auto found = preset.find(64, 127);
  Voice::Voice v1{48000, channelState, 0};
  v1.start(found[0], nrpn);

  found = preset.find(68, 127);
  Voice::Voice v2{48000, channelState, 2};
  v2.start(found[0], nrpn);

  found = preset.find(71, 127);
  Voice::Voice v3{48000, channelState, 4};
  v3.start(found[0], nrpn);

  double sampleRate = 48000.0;
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  int seconds = 3;
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

    if (index == 0 || index == int(sampleCount * 0.5) || index == sampleCount - 1) {
      samples.push_back(s1);
      samples.push_back(s2);
      samples.push_back(s3);
    }

    int vibrato = int(100.0 * index / sampleCount);
    v1.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    v2.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    v3.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);

    if (index == int(sampleCount * 0.95)) {
      v1.releaseKey();
      v2.releaseKey();
      v3.releaseKey();
    }
  }

  std::cout << std::setprecision(12);
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
    XCTAssertEqualWithAccuracy(-0.0285393111408, samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.0574225746095, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0335208065808, samples[5], epsilon);
  }

  XCTAssertEqualWithAccuracy(-2.47968841904e-06, samples[6], epsilon);
  XCTAssertEqualWithAccuracy( 1.00149384252e-06, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-1.50257471887e-06, samples[8], epsilon);

  [self playSamples: buffer count: sampleCount];
}

- (void)testViolinRenderWitSlowAttack {
  const auto& file = contexts.context0.file();
  MIDI::ChannelState channelState;
  MIDI::NRPN nrpn{channelState};
  InstrumentCollection instruments(file);
  Preset preset(file, instruments, file.presets()[80]);
  std::cout << preset.name() << ' ' << preset.bank() << '/' << preset.program() << '\n';

  auto found = preset.find(64, 127);
  Voice::Voice v1{48000, channelState, 0};
  v1.start(found[0], nrpn);

  found = preset.find(68, 127);
  Voice::Voice v2{48000, channelState, 2};
  v2.start(found[0], nrpn);

  found = preset.find(71, 127);
  Voice::Voice v3{48000, channelState, 4};
  v3.start(found[0], nrpn);

  double sampleRate = 48000.0;
  AVAudioFormat* format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:sampleRate channels:2];

  int seconds = 3;
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

    if (index == 0 || index == int(sampleCount * 0.5) || index == sampleCount - 1) {
      samples.push_back(s1);
      samples.push_back(s2);
      samples.push_back(s3);
    }

    int vibrato = int(100.0 * index / sampleCount);
    v1.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    v2.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);
    v3.state().setValue(Voice::State::State::Index::vibratoLFOToPitch, vibrato);

    if (index == int(sampleCount * 0.95)) {
      v1.releaseKey();
      v2.releaseKey();
      v3.releaseKey();
    }
  }

  std::cout << std::setprecision(12);
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
    XCTAssertEqualWithAccuracy(-0.0285393111408, samples[3], epsilon);
    XCTAssertEqualWithAccuracy( 0.0574225746095, samples[4], epsilon);
    XCTAssertEqualWithAccuracy(-0.0335208065808, samples[5], epsilon);
  }

  XCTAssertEqualWithAccuracy(-2.47968841904e-06, samples[6], epsilon);
  XCTAssertEqualWithAccuracy( 1.00149384252e-06, samples[7], epsilon);
  XCTAssertEqualWithAccuracy(-1.50257471887e-06, samples[8], epsilon);

  [self playSamples: buffer count: sampleCount];
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
