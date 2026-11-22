// Copyright © 2026 Brad Howes. All rights reserved.

#include <atomic>
#include <cstdlib>
#include <new>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

#include "SF2Lib/Render/Engine/LoadPresetSysExPayload.hpp"
#include "SF2Util/FixedCapacityVector.hpp"

using namespace SF2;
using namespace SF2::Render::Engine;
using LoadResponse = SF2::IO::File::LoadResponse;

// Count C++ heap allocations made on the current thread while `countAllocations` is set. SF2Lib is linked into this
// test bundle, so its `new` calls (including those inside std::vector and std::make_shared) come through here.
static thread_local bool countAllocations = false;
static std::atomic<int> allocationCount{0};

void* operator new(std::size_t size) {
  if (countAllocations) ++allocationCount;
  if (void* ptr = std::malloc(size == 0 ? 1 : size)) return ptr;
  throw std::bad_alloc();
}

void operator delete(void* ptr) noexcept { std::free(ptr); }

/// Count allocations on this thread while running `block`.
static int allocationsDuring(void (^block)())
{
  allocationCount = 0;
  countAllocations = true;
  block();
  countAllocations = false;
  return allocationCount.load();
}

@interface RealTimeSafetyTests : SamplePlayingTestCase
@end

@implementation RealTimeSafetyTests

- (void)testNoteOnAndRenderDoNotAllocate {
  // §4: note-on used to allocate two vectors in `Preset::find` / `Collection::filter` (plus modulator storage), and
  // free a whole PresetsState in `deletePast`. Play a chord on a real preset and render, counting C++ allocations.
  auto harness{TestEngineHarness{48000.0}};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  auto mixer{harness.createMixer(1.0)};

  // Warm up: the first voice on each slot is the same work as any other, so no warm-up is needed for correctness, but
  // doing one note first keeps one-time library initialisation (e.g. os_log) out of the count.
  harness.sendNoteOn(60, 100);
  harness.renderOnce(mixer);
  harness.sendNoteOff(60);

  auto __block harnessPtr = &harness;
  auto __block mixerPtr = &mixer;
  int count = allocationsDuring(^{
    for (uint8_t key : {60, 64, 67, 72}) harnessPtr->sendNoteOn(key, 100);
    for (int render = 0; render < 10; ++render) harnessPtr->renderOnce(*mixerPtr);
    for (uint8_t key : {60, 64, 67, 72}) harnessPtr->sendNoteOff(key);
    harnessPtr->renderOnce(*mixerPtr);
  });
  XCTAssertGreaterThan(harness.engine().activeVoiceCount(), size_t(0));
  XCTAssertEqual(count, 0);
}

- (void)testProgramChangeRunsOnWorkQueue {
  // §4: a program change used to load the preset's samples on the render thread. Now the render thread only stops the
  // voices and queues the change; until it completes, notes are ignored and nothing renders.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  auto mixer{harness.createMixer(0.5)};
  harness.sendNoteOn(60, 100);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(1));

  harness.suspendWorkQueue();
  harness.sendRaw(std::array<uint8_t, 3>{0xC0, 23, 0});
  XCTAssertEqual(engine.activeVoiceCount(), size_t(0));
  XCTAssertEqual(engine.presetChangesPending(), 1);
  XCTAssertEqual(engine.activePresetName(), std::string("Piano 1"));
  harness.sendNoteOn(64, 100);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(0));

  harness.resumeWorkQueue();
  harness.drainWorkQueue();
  XCTAssertEqual(engine.presetChangesPending(), 0);
  XCTAssertEqual(engine.activePresetName(), std::string("Bandoneon"));
  harness.sendNoteOn(64, 100);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(1));
}

- (void)testProgramChangeWithNothingLoadedDoesNotBlockNotes {
  // `changeProgram_RT` used to bump presetChangesPending before checking for a state, and never undo it, so after a
  // program change with no file loaded every later note-on was ignored.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  harness.sendRaw(std::array<uint8_t, 3>{0xC0, 5, 0});
  harness.drainWorkQueue();
  XCTAssertEqual(engine.presetChangesPending(), 0);

  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  harness.sendNoteOn(60, 100);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(1));
}

- (void)testBookmarkLoadFailureDoesNotBlockNotes {
  // A bookmark that does not resolve used to return without undoing presetChangesPending.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  NSData* garbage = [@"not a bookmark" dataUsingEncoding:NSUTF8StringEncoding];
  XCTAssertEqual(engine.loadBookmarkAndPreset(garbage, 0), LoadResponse::notFound);
  XCTAssertEqual(engine.presetChangesPending(), 0);
  harness.sendNoteOn(60, 100);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(1));
}

- (void)testReplacedPresetsStatesAreFreedOffRenderThread {
  // §3.2: loading a file while notes sound left the old voices playing the old state's samples, and the old state was
  // deleted at the next note-on (use-after-free); `deletePast` also freed only one level, leaking older states. Now the
  // render thread stops voices from the old state when it sees the new one, and replaced states are freed once the
  // render thread has moved on.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  auto mixer{harness.createMixer(2.0)};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  harness.sendNoteOn(60, 100);
  harness.renderOnce(mixer);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(1));

  // Load another file while the voice sounds. The old state is retired, not freed: the render thread still uses it.
  XCTAssertEqual(harness.load(self.contexts->context2.path(), 0), LoadResponse::ok);
  XCTAssertEqual(harness.retiredPresetsStateCount(), size_t(1));
  XCTAssertEqual(engine.activeVoiceCount(), size_t(1));

  // The next render switches to the new state and stops the old voice.
  harness.renderOnce(mixer);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(0));

  // Repeated loads, each followed by a render, never leave more than the most recently replaced state waiting.
  for (int count = 0; count < 10; ++count) {
    XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
    harness.sendNoteOn(60, 100);
    harness.renderOnce(mixer);
    XCTAssertEqual(engine.activeVoiceCount(), size_t(1));
    XCTAssertLessThanOrEqual(harness.retiredPresetsStateCount(), size_t(1));
  }

  // Once rendering stops, nothing retired is in use any more.
  engine.doRenderingStateChanged(false);
  XCTAssertEqual(harness.retiredPresetsStateCount(), size_t(0));
}

- (void)testSysExShorterThanHeaderIsIgnored {
  // `doMIDIEvent` used to read `data[1]` and `data[2]` before checking the length.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  harness.sendRaw(std::vector<uint8_t>{0xF0});
  harness.sendRaw(std::vector<uint8_t>{0xF0, 0xF7});
  harness.drainWorkQueue();
  XCTAssertEqual(engine.presetChangesPending(), 0);
  XCTAssertEqual(engine.activePresetName(), std::string("Piano 1"));
}

- (void)testSysExWithBadOverrideCountIsRejected {
  // `overrideCount` used to come straight off the wire, so a large value read (and copied) far past the message.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  auto payload = Engine::createLoadFileUsePresetPayload(self.contexts->context2.path(), 0, {});
  reinterpret_cast<LoadPresetSysExPayload*>(payload.data())->overrideCount = 1'000'000'000;
  harness.sendRaw(payload);
  harness.drainWorkQueue();
  XCTAssertEqual(engine.presetChangesPending(), 0);
  XCTAssertEqual(engine.activePresetName(), std::string("Piano 1"));
  harness.sendNoteOn(60, 100);
  XCTAssertEqual(engine.activeVoiceCount(), size_t(1));
}

- (void)testSysExWithInvalidBookmarkIsRejected {
  // The bookmark is decoded on the work queue now. Invalid Base64 must not leave presetChangesPending set.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  NSData* bookmark = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
  auto payload = Engine::createLoadBookmarkUsePresetPayload(bookmark, 0, {});
  // Replace the Base64 text with characters that are not Base64.
  for (size_t index = sizeof(LoadPresetSysExPayload); index < payload.size() - 1; ++index) payload[index] = '*';
  harness.sendRaw(payload);
  harness.drainWorkQueue();
  XCTAssertEqual(engine.presetChangesPending(), 0);
  XCTAssertEqual(engine.activePresetName(), std::string("Piano 1"));
}

- (void)testSysExLoadStillWorks {
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  harness.sendRaw(Engine::createLoadFileUsePresetPayload(self.contexts->context2.path(), 0, {}));
  harness.drainWorkQueue();
  XCTAssertEqual(engine.presetChangesPending(), 0);
  XCTAssertEqual(engine.activePresetName(), std::string("Nice Piano"));
}

- (void)testSysExRequestsBeyondSlotCountAreDropped {
  // SysEx requests are copied into a fixed set of slots on the render thread. With the work queue held back, the
  // fifth request finds no free slot and is dropped instead of allocating.
  auto harness{TestEngineHarness{48000.0}};
  auto& engine{harness.engine()};
  XCTAssertEqual(harness.load(self.contexts->context0.path(), 0), LoadResponse::ok);
  auto payload = Engine::createLoadFileUsePresetPayload("", 1, {});
  harness.suspendWorkQueue();
  for (int count = 0; count < 5; ++count) harness.sendRaw(payload);
  XCTAssertEqual(engine.presetChangesPending(), 4);
  harness.resumeWorkQueue();
  harness.drainWorkQueue();
  XCTAssertEqual(engine.presetChangesPending(), 0);
  XCTAssertEqual(engine.activePresetName(), std::string("Piano 2"));
}

- (void)testFindIsCappedAtFixedCapacity {
  // `Preset::find` fills a fixed-capacity collection. An instrument with more overlapping zones than that still plays,
  // using the first `maxConfigsPerNote` zones.
  auto builder = SF2Builder::minimal();
  const size_t zoneCount = Render::Preset::maxConfigsPerNote + 6;
  builder.igen.clear();
  builder.ibag.clear();
  for (size_t index = 0; index < zoneCount; ++index) {
    builder.ibag.push_back({uint16_t(index), 0});
    builder.igen.push_back({SF2Builder::genSampleID, 0});
  }
  builder.ibag.push_back({uint16_t(zoneCount), 0});
  builder.igen.push_back({0, 0});
  builder.inst[1].bagIndex = uint16_t(zoneCount);
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibManyZones.sf2";
  builder.writeTo(path);

  auto harness{TestEngineHarness{48000.0}};
  XCTAssertEqual(harness.load(path, 0), LoadResponse::ok);
  harness.sendNoteOn(69, 100);
  XCTAssertEqual(harness.engine().activeVoiceCount(), Render::Preset::maxConfigsPerNote);
}

@end

/// Element type that is neither default-constructible nor assignable, like `Voice::State::Config`.
struct Tracked {
  static inline int alive = 0;
  const int& ref;
  explicit Tracked(const int& value) : ref{value} { ++alive; }
  Tracked(const Tracked& rhs) : ref{rhs.ref} { ++alive; }
  ~Tracked() { --alive; }
  Tracked& operator=(const Tracked&) = delete;
};

@interface FixedCapacityVectorTests : XCTestCase
@end

@implementation FixedCapacityVectorTests

- (void)testFillsToCapacityThenRefuses {
  int value = 7;
  {
    Utils::FixedCapacityVector<Tracked, 3> vector;
    XCTAssertTrue(vector.empty());
    XCTAssertTrue(vector.emplace_back(value));
    XCTAssertTrue(vector.emplace_back(value));
    XCTAssertTrue(vector.emplace_back(value));
    XCTAssertTrue(vector.full());
    XCTAssertFalse(vector.emplace_back(value));
    XCTAssertEqual(vector.size(), size_t(3));
    XCTAssertEqual(Tracked::alive, 3);
    XCTAssertEqual(vector[2].ref, 7);
    XCTAssertEqual(&vector.at(1).ref, &value);
    bool threw = false;
    try { (void)vector.at(3); } catch (const std::out_of_range&) { threw = true; }
    XCTAssertTrue(threw);

    auto copy{vector};
    XCTAssertEqual(copy.size(), size_t(3));
    XCTAssertEqual(Tracked::alive, 6);

    auto moved{std::move(copy)};
    XCTAssertEqual(moved.size(), size_t(3));
    XCTAssertTrue(copy.empty());
    XCTAssertEqual(Tracked::alive, 6);

    int sum = 0;
    for (const auto& item : moved) sum += item.ref;
    XCTAssertEqual(sum, 21);
  }
  XCTAssertEqual(Tracked::alive, 0);
}

@end
