// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SF2File/Entity/Generator/Amount.hpp"
#include "SF2Lib/Render/Range.hpp"

using namespace SF2::Render;
using namespace SF2::Entity::Generator;

@interface RangeTests : XCTestCase
@end

@implementation RangeTests

- (void)testRange {
  Range<int> range(0, 50);
  XCTAssertEqual(0, range.low());
  XCTAssertEqual(50, range.high());

  XCTAssertTrue(range.contains(0));
  XCTAssertTrue(range.contains(30));
  XCTAssertTrue(range.contains(50));

  XCTAssertFalse(range.contains(-1));
  XCTAssertFalse(range.contains(51));
}

- (void)testRangeConversion {
  Range<int> range(Amount(0x3200).low(), Amount(0x3200).high());
  XCTAssertEqual(0, range.low());
  XCTAssertEqual(50, range.high());

  range = Range<int>(Amount(0x7F7F).low(), Amount(0x7F7F).high());
  XCTAssertEqual(127, range.low());
  XCTAssertEqual(127, range.high());

  range = Range<int>(Amount(0x00FF).low(), Amount(0x00FF).high());
  XCTAssertEqual(255, range.low());
  XCTAssertEqual(0, range.high());
}

@end
