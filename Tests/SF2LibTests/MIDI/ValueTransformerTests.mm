// Copyright © 2020 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SF2Lib/Entity/Modulator/Source.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

using namespace SF2::MIDI;
using ValueTransformer = SF2::MIDI::ValueTransformer;
using Source = SF2::Entity::Modulator::Source;

@interface ValueTransformerTests : XCTestCase
@property (nonatomic, assign) SF2::Float epsilon;
@end

@implementation ValueTransformerTests

- (void)setUp {
  self.epsilon = 0.0000001;
}

- (void)tearDown {
}

static ValueTransformer makeValueTransformer(ValueTransformer::Kind kind, ValueTransformer::Polarity polarity,
                                             ValueTransformer::Direction direction) {
  auto source = Source(Source::GeneralIndex::none);
  if (polarity == ValueTransformer::Polarity::bipolar) source = source.bipolar();
  if (direction == ValueTransformer::Direction::descending) source = source.negative();
  switch (kind) {
    case ValueTransformer::Kind::linear: source = source.linear(); break;
    case ValueTransformer::Kind::concave: source = source.concave(); break;
    case ValueTransformer::Kind::convex: source = source.convex(); break;
    case ValueTransformer::Kind::switched: source = source.switched(); break;
  }
  return ValueTransformer(source);
}

- (void)testLinearAscendingUnipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::linear, ValueTransformer::Polarity::unipolar,
                                ValueTransformer::Direction::ascending);
  XCTAssertEqualWithAccuracy(0.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.25, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.75, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(127.0 / 128.0, z(127), self.epsilon);
}

- (void)testLinearDescendingUnipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::linear, ValueTransformer::Polarity::unipolar,
                                ValueTransformer::Direction::descending);
  XCTAssertEqualWithAccuracy(1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.75, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.25, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0 - 127.0 / 128.0, z(127), self.epsilon);
}

- (void)testLinearAscendingBipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::linear, ValueTransformer::Polarity::bipolar,
                                ValueTransformer::Direction::ascending);
  XCTAssertEqualWithAccuracy(-1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.5, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(127.0 / 128.0 * 2.0 - 1.0, z(127), self.epsilon);
}

- (void)testLinearDescendingBipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::linear, ValueTransformer::Polarity::bipolar,
                                ValueTransformer::Direction::descending);
  XCTAssertEqualWithAccuracy(1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.5, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.0, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.5, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy((1.0 - 127.0 / 128.0) * 2 - 1.0, z(127), self.epsilon);
}

- (void)testConcaveAscendingUnipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::concave, ValueTransformer::Polarity::unipolar,
                                ValueTransformer::Direction::ascending);
  XCTAssertEqualWithAccuracy(0.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.052533381528, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.126859654793, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.255184177967, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(0.876584883732, z(126), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(127), self.epsilon);
}

- (void)testConcaveDescendingUnipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::concave, ValueTransformer::Polarity::unipolar,
                                ValueTransformer::Direction::descending);
  XCTAssertEqualWithAccuracy(1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.249439059432, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.124009894572, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.0506385366318, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, z(127), self.epsilon);
}

- (void)testConcaveAscendingBipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::concave, ValueTransformer::Polarity::bipolar,
                                ValueTransformer::Direction::ascending);
  XCTAssertEqualWithAccuracy(-1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.894933236944, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.746280690415, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.489631644065, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(127), self.epsilon);
}

- (void)testConcaveDescendingBipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::concave, ValueTransformer::Polarity::bipolar,
                                ValueTransformer::Direction::descending);
  XCTAssertEqualWithAccuracy(1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.501121881137, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.751980210857, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(-0.898722926736, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(-1.0, z(127), self.epsilon);
}

- (void)testConvexAscendingUnipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::convex, ValueTransformer::Polarity::unipolar,
                                ValueTransformer::Direction::ascending);
  XCTAssertEqualWithAccuracy(0.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.750560940568, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.875990105428, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.949361463368, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(127), self.epsilon);
}

- (void)testConvexDescendingUnipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::convex, ValueTransformer::Polarity::unipolar,
                                ValueTransformer::Direction::descending);
  XCTAssertEqualWithAccuracy(1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.947466618472, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.873140345207, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.744815822033, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, z(127), self.epsilon);
}

- (void)testConvexAscendingBipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::convex, ValueTransformer::Polarity::bipolar,
                                ValueTransformer::Direction::ascending);
  XCTAssertEqualWithAccuracy(-1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.501121881137, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.751980210857, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.898722926736, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(127), self.epsilon);
}

- (void)testConvexDescendingBipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::convex, ValueTransformer::Polarity::bipolar,
                                ValueTransformer::Direction::descending);
  XCTAssertEqualWithAccuracy(1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.894933236944, z(32), self.epsilon);
  XCTAssertEqualWithAccuracy(0.746280690415, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.489631644065, z(96), self.epsilon);
  XCTAssertEqualWithAccuracy(-1.0, z(127), self.epsilon);
}

- (void)testSwitchedAscendingUnipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::switched, ValueTransformer::Polarity::unipolar,
                                ValueTransformer::Direction::ascending);
  XCTAssertEqualWithAccuracy(0.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, z(63), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(127), self.epsilon);
}

- (void)testSwitchedDescendingUnipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::switched, ValueTransformer::Polarity::unipolar,
                                ValueTransformer::Direction::descending);
  XCTAssertEqualWithAccuracy(1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(63), self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(0.0, z(127), self.epsilon);
}

- (void)testSwitchedAscendingBipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::switched, ValueTransformer::Polarity::bipolar,
                                ValueTransformer::Direction::ascending);
  XCTAssertEqualWithAccuracy(-1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(-1.0, z(63), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(127), self.epsilon);
}

- (void)testSwitchedDescendingBipolar {
  auto z = makeValueTransformer(ValueTransformer::Kind::switched, ValueTransformer::Polarity::bipolar,
                                ValueTransformer::Direction::descending);
  XCTAssertEqualWithAccuracy(1.0, z(0), self.epsilon);
  XCTAssertEqualWithAccuracy(1.0, z(63), self.epsilon);
  XCTAssertEqualWithAccuracy(-1.0, z(64), self.epsilon);
  XCTAssertEqualWithAccuracy(-1.0, z(127), self.epsilon);
}

@end
