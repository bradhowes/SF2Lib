// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include "SampleBasedContexts.hpp"

#include "SF2File/IO/File.hpp"
#include "SF2Lib/Render/Preset.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Voice;

@interface PresetTests : XCTestCase

@property (nonatomic) SampleBasedContexts* contexts;

@end

@implementation PresetTests

@synthesize contexts;

- (void)setUp {
  self.contexts = new SampleBasedContexts();
  [super setUp];
}

- (void)tearDown {
  delete self.contexts;
  [super tearDown];
}
- (void)testRolandPianoPreset {
  auto& file{self.contexts->context2.file()};
  XCTAssertEqual(size_t(1), file.presets().size());

  Preset preset{self.contexts->context2.preset(0)};
  XCTAssertEqual(size_t(6), preset.zones().size());
  XCTAssertFalse(preset.hasGlobalZone());

  auto found = preset.find(64, 10);
  XCTAssertEqual(size_t(2), found.size());

  State::State left = self.contexts->context2.makeState(found[0]);
  XCTAssertEqual(-500, left.unmodulated(Entity::Generator::Index::pan));
  XCTAssertEqual(1902, left.unmodulated(Entity::Generator::Index::releaseVolumeEnvelope));
  XCTAssertEqual(7437, left.unmodulated(Entity::Generator::Index::initialFilterCutoff));
  XCTAssertEqual(23, left.unmodulated(Entity::Generator::Index::sampleID));
  XCTAssertEqual(0, left.unmodulated(Entity::Generator::Index::startAddressOffset));
  XCTAssertEqual(0, left.unmodulated(Entity::Generator::Index::startAddressCoarseOffset));
  XCTAssertEqual(0, left.unmodulated(Entity::Generator::Index::endAddressOffset));
  XCTAssertEqual(0, left.unmodulated(Entity::Generator::Index::endAddressCoarseOffset));

  State::State right = self.contexts->context2.makeState(found[1]);
  XCTAssertEqual(500, right.unmodulated(Entity::Generator::Index::pan));
  XCTAssertEqual(1902, right.unmodulated(Entity::Generator::Index::releaseVolumeEnvelope));
  XCTAssertEqual(7437, right.unmodulated(Entity::Generator::Index::initialFilterCutoff));
  XCTAssertEqual(22, right.unmodulated(Entity::Generator::Index::sampleID));
  XCTAssertEqual(0, right.unmodulated(Entity::Generator::Index::startAddressOffset));
  XCTAssertEqual(0, right.unmodulated(Entity::Generator::Index::startAddressCoarseOffset));
  XCTAssertEqual(0, right.unmodulated(Entity::Generator::Index::endAddressOffset));
  XCTAssertEqual(0, right.unmodulated(Entity::Generator::Index::endAddressCoarseOffset));
}

@end
