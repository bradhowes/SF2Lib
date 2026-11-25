// Copyright © 2026 Brad Howes. All rights reserved.

#include <functional>
#include <set>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

using namespace SF2;
using LoadResponse = SF2::IO::File::LoadResponse;
using Voice = SF2::Render::Voice::Voice;

// SF2.01 7.10: "If sfSampleType indicates a left or right sample, then wSampleLink is the sample header index of the
// associated right or left stereo sample respectively. Both samples should be played entirely synchronously, with
// their pitch controlled by the right sample's generators. All non-pitch generators should apply as normal".

static constexpr uint16_t genPan = 17;
static constexpr uint16_t genVelRange = 44;
static constexpr uint16_t genCoarseTune = 51;
static constexpr uint16_t genFineTune = 52;
static constexpr uint16_t genAttenuation = 48;
static constexpr uint16_t monoSample = 1;
static constexpr uint16_t rightSample = 2;
static constexpr uint16_t leftSample = 4;
static constexpr uint32_t sineCount = SF2Builder::sineSampleCount;

/// Description of the two instrument zones of the test file. Zone 0 plays sample 0 ("Right"), zone 1 sample 1 ("Left").
struct StereoFile {
  uint16_t rightType{rightSample};
  uint16_t leftType{leftSample};
  uint16_t rightLink{1};
  uint16_t leftLink{0};
  std::vector<SF2Builder::Gen> rightGens{};  // extra generators for the right zone
  std::vector<SF2Builder::Gen> leftGens{};   // extra generators for the left zone
  uint32_t rightCount{sineCount};
  uint16_t rightModes{1};
};

/// Append a sine sample of `count` values with the given period, its 46 padding samples and its header.
static void addSine(SF2Builder& builder, const std::string& name, uint32_t count, double period, uint16_t type,
                    uint16_t link)
{
  auto start = uint32_t(builder.samples.size());
  for (uint32_t index = 0; index < count; ++index) {
    builder.samples.push_back(int16_t(std::lround(16'000.0 * std::sin(2.0 * M_PI * double(index) / period))));
  }
  builder.samples.insert(builder.samples.end(), 46, 0);
  uint32_t loopStart = count > 200 ? 100 : 8;
  uint32_t loopEnd = count > 200 ? count - 100 : count - 8;
  builder.shdr.insert(builder.shdr.end() - 1, {name, start, start + count, start + loopStart, start + loopEnd, 44'100,
    69, 0, link, type});
}

static SF2Builder makeBuilder(const StereoFile& desc)
{
  auto builder = SF2Builder::minimal();
  builder.samples.clear();
  builder.shdr = {{"EOS", 0, 0, 0, 0, 0, 0, 0, 0, 0}};
  addSine(builder, "Right", desc.rightCount, 100.0, desc.rightType, desc.rightLink);
  addSine(builder, "Left", sineCount, 77.0, desc.leftType, desc.leftLink);

  auto zone = [](std::vector<SF2Builder::Gen> extra, int16_t pan, uint16_t modes, uint16_t sampleID) {
    // Range generators must come first and sampleID last (SF2.01 8.1.2).
    std::vector<SF2Builder::Gen> gens;
    for (const auto& gen : extra) if (gen.oper == genVelRange) gens.push_back(gen);
    gens.push_back({genPan, uint16_t(pan)});
    for (const auto& gen : extra) if (gen.oper != genVelRange) gens.push_back(gen);
    gens.push_back({SF2Builder::genSampleModes, modes});
    gens.push_back({SF2Builder::genSampleID, sampleID});
    return gens;
  };
  auto right = zone(desc.rightGens, 500, desc.rightModes, 0);
  auto left = zone(desc.leftGens, -500, 1, 1);
  builder.igen = right;
  builder.igen.insert(builder.igen.end(), left.begin(), left.end());
  builder.igen.push_back({0, 0});
  builder.ibag = {{0, 0}, {uint16_t(right.size()), 0}, {uint16_t(right.size() + left.size()), 0}};
  builder.inst[1].bagIndex = 2;
  return builder;
}

static std::string writeFile(const StereoFile& desc, const std::string& name)
{
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibStereo-" + name + ".sf2";
  makeBuilder(desc).writeTo(path);
  return path;
}

/// The two output channels of a render.
struct Channels {
  std::vector<AUValue> left;
  std::vector<AUValue> right;
};

/// Play key 69 at `velocity` for `seconds` and return both dry channels.
static Channels render(const std::string& path, uint8_t velocity = 127, double seconds = 0.1,
                       std::function<void(TestEngineHarness&)> afterNoteOn = nullptr)
{
  auto harness{TestEngineHarness{48000.0}};
  if (harness.load(path, 0) != LoadResponse::ok) return {};
  auto mixer{harness.createMixer(seconds)};
  harness.sendNoteOn(69, velocity);
  if (afterNoteOn) afterNoteOn(harness);
  harness.renderToEnd(mixer);
  auto count = harness.bufferFrameCount();
  const AUValue* left = harness.dryBuffer().floatChannelData[0];
  const AUValue* right = harness.dryBuffer().floatChannelData[1];
  return {std::vector<AUValue>(left, left + count), std::vector<AUValue>(right, right + count)};
}

static double peak(const std::vector<AUValue>& samples)
{
  double value = 0.0;
  for (auto sample : samples) value = std::max(value, std::abs(double(sample)));
  return value;
}

/// @returns the indices of the active voices
static std::vector<size_t> activeVoices(TestEngineHarness& harness)
{
  std::vector<size_t> found;
  for (size_t index = 0; index < Render::Engine::traits::maxVoiceCount; ++index) {
    if (harness.voice(index).isActive()) found.push_back(index);
  }
  return found;
}

@interface StereoLinkTests : XCTestCase
@end

@implementation StereoLinkTests

- (void)testPanningSeparatesTheChannels {
  // Sanity check of the test file: each output channel carries only one of the two samples.
  auto both = render(writeFile({}, "plain"));
  XCTAssertGreaterThan(peak(both.left), 0.1);
  XCTAssertGreaterThan(peak(both.right), 0.1);
  auto onlyRight = render(writeFile({.leftGens = {{genAttenuation, 1440}}}, "silent-left"));
  XCTAssertLessThan(peak(onlyRight.left), 1.0e-6);
}

- (void)testVoicesOfAPairAreLinked {
  size_t linked = 0;
  bool rightLeads = false;
  render(writeFile({}, "linked"), 127, 0.01, [&](TestEngineHarness& harness) {
    for (auto index : activeVoices(harness)) {
      auto& voice = harness.voice(index);
      if (voice.partner() == Voice::noPartner) continue;
      ++linked;
      XCTAssertEqual(harness.voice(voice.partner()).partner(), index);
      if (voice.isPitchLeader()) rightLeads = voice.state().unmodulated(Entity::Generator::Index::pan) == 500;
    }
  });
  XCTAssertEqual(linked, size_t(2));
  XCTAssertTrue(rightLeads);
}

- (void)testLeftSampleFollowsTheRightSamplesPitch {
  // An octave up on the left zone is ignored: the left sample plays at the right zone's pitch. Previously it played
  // an octave up.
  auto reference = render(writeFile({}, "reference"));
  auto detunedLeft = render(writeFile({.leftGens = {{genCoarseTune, 12}}}, "detuned-left"));
  XCTAssertTrue(detunedLeft.left == reference.left);
  XCTAssertTrue(detunedLeft.right == reference.right);

  // Guard against a vacuous test: the same detuning on an unlinked (mono) pair is heard.
  auto mono = render(writeFile({.rightType = monoSample, .leftType = monoSample, .leftGens = {{genCoarseTune, 12}}},
                               "detuned-mono"));
  XCTAssertFalse(mono.left == reference.left);
}

- (void)testRightSamplesPitchGeneratorsDriveBoth {
  // Fine tune on the right zone only moves both channels: the left one sounds like a pair where both zones have it.
  auto rightOnly = render(writeFile({.rightGens = {{genFineTune, 50}}}, "right-tuned"));
  auto bothTuned = render(writeFile({.rightGens = {{genFineTune, 50}}, .leftGens = {{genFineTune, 50}}}, "both-tuned"));
  auto untuned = render(writeFile({}, "untuned"));
  XCTAssertTrue(rightOnly.left == bothTuned.left);
  XCTAssertFalse(rightOnly.left == untuned.left);
}

- (void)testNonPitchGeneratorsApplyAsNormal {
  // Attenuation on the left zone still applies to the left channel only.
  auto attenuated = render(writeFile({.leftGens = {{genAttenuation, 200}}}, "attenuated-left"));
  auto plain = render(writeFile({}, "plain-2"));
  XCTAssertTrue(attenuated.right == plain.right);
  XCTAssertLessThan(peak(attenuated.left), 0.2 * peak(plain.left));
  XCTAssertGreaterThan(peak(attenuated.left), 0.0);
}

- (void)testOneWayLinkIsNotAPair {
  // The left header links back to itself rather than to the right header, so the two are not a stereo pair and the
  // left zone keeps its own (octave up) pitch.
  auto oneWay = render(writeFile({.leftLink = 1, .leftGens = {{genCoarseTune, 12}}}, "one-way"));
  auto mono = render(writeFile({.rightType = monoSample, .leftType = monoSample, .leftGens = {{genCoarseTune, 12}}},
                               "one-way-mono"));
  XCTAssertTrue(oneWay.left == mono.left);
}

- (void)testHalfAPairPlaysOnItsOwn {
  // The left zone only answers velocities 100-127, so a softer note starts just the right voice, unlinked.
  size_t voices = 0;
  size_t linked = 0;
  render(writeFile({.leftGens = {{genVelRange, uint16_t(100 | (127 << 8))}}}, "half"), 64, 0.01,
         [&](TestEngineHarness& harness) {
    for (auto index : activeVoices(harness)) {
      ++voices;
      if (harness.voice(index).partner() != Voice::noPartner) ++linked;
    }
  });
  XCTAssertEqual(voices, size_t(1));
  XCTAssertEqual(linked, size_t(0));
}

- (void)testStealingOneHalfUnlinksTheOther {
  // Fill every voice: one pair (velocity 127) and then single right voices (velocity 64, the left zone does not
  // answer). The next note steals the oldest voice, one half of the pair. The other half must carry on, unlinked.
  auto path = writeFile({.leftGens = {{genVelRange, uint16_t(100 | (127 << 8))}}}, "steal");
  auto harness{TestEngineHarness{48000.0}};
  XCTAssertEqual(harness.load(path, 0), LoadResponse::ok);
  auto mixer{harness.createMixer(0.1)};
  harness.sendNoteOn(69, 127);
  std::set<size_t> pair;
  for (auto index : activeVoices(harness)) pair.insert(index);
  XCTAssertEqual(pair.size(), size_t(2));
  harness.renderForCount(mixer, 64);
  for (size_t note = 0; note < Render::Engine::traits::maxVoiceCount - 2; ++note) {
    harness.sendNoteOn(uint8_t(note % 128), 64);
  }
  XCTAssertEqual(harness.engine().activeVoiceCount(), Render::Engine::traits::maxVoiceCount);

  harness.sendNoteOn(70, 64);  // steals the oldest voice
  size_t survivors = 0;
  for (auto index : pair) {
    auto& voice = harness.voice(index);
    if (voice.initiatingKey() == 69) {
      ++survivors;
      XCTAssertTrue(voice.isActive());
      XCTAssertEqual(voice.partner(), Voice::noPartner);
    } else {
      XCTAssertEqual(voice.initiatingKey(), 70);  // the stolen half now plays the new note
      XCTAssertEqual(voice.partner(), Voice::noPartner);
    }
  }
  XCTAssertEqual(survivors, size_t(1));
  harness.renderForCount(mixer, 512);  // renders without touching the old pairing
}

- (void)testSheddingReleasesBothHalvesOfAPair {
  // With room for 2 voices, a newer single voice and an older pair: the pair is shed together. Previously only the
  // oldest voice (one half) was released, leaving the other channel playing alone.
  auto path = writeFile({.leftGens = {{genVelRange, uint16_t(100 | (127 << 8))}}}, "shed");
  auto harness{TestEngineHarness{48000.0}};
  XCTAssertEqual(harness.load(path, 0), LoadResponse::ok);
  auto mixer{harness.createMixer(0.1)};
  harness.sendNoteOn(69, 127);  // pair
  std::vector<size_t> pair = activeVoices(harness);
  XCTAssertEqual(pair.size(), size_t(2));
  harness.renderForCount(mixer, 64);
  harness.sendNoteOn(72, 64);   // single, newest

  static uint64_t now = 0;
  harness.enableRenderingBudget(1.0, [] () noexcept -> uint64_t { return now; });
  harness.setAverageVoiceFrameNanoseconds(double(harness.frameNanoseconds()) / 2.5);  // 2 voices fit
  harness.renderForCount(mixer, 48);
  for (auto index : pair) {
    XCTAssertTrue(harness.voice(index).isFastReleasing(), @"voice %zu", index);
  }
}

- (void)testFollowerContinuesWhenTheLeaderEnds {
  // The right sample is short and does not loop, so the leader ends long before the left (looping) sample. The left
  // voice carries on, unlinked, with its own pitch.
  auto path = writeFile({.rightCount = 300, .rightModes = 0}, "leader-ends");
  auto harness{TestEngineHarness{48000.0}};
  XCTAssertEqual(harness.load(path, 0), LoadResponse::ok);
  auto mixer{harness.createMixer(0.2)};
  harness.sendNoteOn(69, 127);
  XCTAssertEqual(harness.engine().activeVoiceCount(), size_t(2));
  harness.renderForDuration(mixer, 0.1);
  auto remaining = activeVoices(harness);
  XCTAssertEqual(remaining.size(), size_t(1));
  if (!remaining.empty()) {
    XCTAssertEqual(harness.voice(remaining[0]).partner(), Voice::noPartner);
    XCTAssertEqual(harness.voice(remaining[0]).state().unmodulated(Entity::Generator::Index::pan), -500);
  }
  harness.renderToEnd(mixer);
  XCTAssertGreaterThan(std::abs(harness.lastDrySample(0)), 0.0);  // left channel still sounding
}

@end
