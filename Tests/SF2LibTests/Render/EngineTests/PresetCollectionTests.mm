// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Render/PresetCollection.hpp"

using namespace SF2::Render;
using namespace SF2::Render::Engine;

@interface PresetCollectionTests : XCTestCase

@end

@implementation PresetCollectionTests {
  SampleBasedContexts contexts;
}

- (void)testLoading {
  PresetCollection presets;
  XCTAssertEqual(0, presets.size());

  presets.build(contexts.context0.file());
  XCTAssertEqual(235, presets.size());

  presets.clear();
  XCTAssertEqual(0, presets.size());
}

- (void)testOrdering {
  PresetCollection presets;
  presets.build(contexts.context0.file());

  XCTAssertEqual(presets.size(), 235);

  XCTAssertEqual(presets[0].configuration().name(), "Piano 1");
  XCTAssertEqual(presets[0].configuration().bank(), 0);
  XCTAssertEqual(presets[0].configuration().program(), 0);

  XCTAssertEqual(presets[1].configuration().name(), "Piano 2");
  XCTAssertEqual(presets[1].configuration().bank(), 0);
  XCTAssertEqual(presets[1].configuration().program(), 1);

  XCTAssertEqual(presets[2].configuration().name(), "Piano 3");
  XCTAssertEqual(presets[2].configuration().bank(), 0);
  XCTAssertEqual(presets[2].configuration().program(), 2);

  XCTAssertEqual(presets[presets.size() - 3].configuration().name(), "Brush");
  XCTAssertEqual(presets[presets.size() - 3].configuration().bank(), 128);
  XCTAssertEqual(presets[presets.size() - 3].configuration().program(), 40);

  XCTAssertEqual(presets[presets.size() - 2].configuration().name(), "Orchestra");
  XCTAssertEqual(presets[presets.size() - 2].configuration().bank(), 128);
  XCTAssertEqual(presets[presets.size() - 2].configuration().program(), 48);

  XCTAssertEqual(presets[presets.size() - 1].configuration().name(), "SFX");
  XCTAssertEqual(presets[presets.size() - 1].configuration().bank(), 128);
  XCTAssertEqual(presets[presets.size() - 1].configuration().program(), 56);
}

- (void)testLocate {
  PresetCollection presets;
  presets.build(contexts.context0.file());
  XCTAssertEqual(presets.locatePreset(0, 0)->configuration().name(), "Piano 1");
  // std::cout << presets.locate(128, 0)->name() << '\n';
  XCTAssertEqual(presets.locatePreset(128, 0)->configuration().name(), "Standard");
  XCTAssertEqual(presets.locatePreset(128, 56)->configuration().name(), "SFX");

  XCTAssertEqual(presets.locatePreset(127, 0), nullptr);
  XCTAssertEqual(presets.locatePreset(128, 57), nullptr);
  XCTAssertEqual(presets.locatePreset(-1, -1), nullptr);
}

@end
