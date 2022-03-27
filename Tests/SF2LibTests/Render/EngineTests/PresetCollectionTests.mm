// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "../../SampleBasedContexts.hpp"

#include "SF2Lib/Render/Engine/PresetCollection.hpp"

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

  XCTAssertEqual(presets[0].name(), "Piano 1");
  XCTAssertEqual(presets[0].bank(), 0);
  XCTAssertEqual(presets[0].program(), 0);

  XCTAssertEqual(presets[1].name(), "Piano 2");
  XCTAssertEqual(presets[1].bank(), 0);
  XCTAssertEqual(presets[1].program(), 1);

  XCTAssertEqual(presets[2].name(), "Piano 3");
  XCTAssertEqual(presets[2].bank(), 0);
  XCTAssertEqual(presets[2].program(), 2);

  XCTAssertEqual(presets[presets.size() - 3].name(), "Brush");
  XCTAssertEqual(presets[presets.size() - 3].bank(), 128);
  XCTAssertEqual(presets[presets.size() - 3].program(), 40);

  XCTAssertEqual(presets[presets.size() - 2].name(), "Orchestra");
  XCTAssertEqual(presets[presets.size() - 2].bank(), 128);
  XCTAssertEqual(presets[presets.size() - 2].program(), 48);

  XCTAssertEqual(presets[presets.size() - 1].name(), "SFX");
  XCTAssertEqual(presets[presets.size() - 1].bank(), 128);
  XCTAssertEqual(presets[presets.size() - 1].program(), 56);
}

- (void)testLocate {
  PresetCollection presets;
  presets.build(contexts.context0.file());
  XCTAssertEqual(presets.locatePreset(0, 0)->name(), "Piano 1");
  // std::cout << presets.locate(128, 0)->name() << '\n';
  XCTAssertEqual(presets.locatePreset(128, 0)->name(), "Standard");
  XCTAssertEqual(presets.locatePreset(128, 56)->name(), "SFX");

  XCTAssertEqual(presets.locatePreset(127, 0), nullptr);
  XCTAssertEqual(presets.locatePreset(128, 57), nullptr);
  XCTAssertEqual(presets.locatePreset(-1, -1), nullptr);
}

@end
