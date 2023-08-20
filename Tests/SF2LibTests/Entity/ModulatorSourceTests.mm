// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SF2Lib/Entity/Modulator/Source.hpp"

using namespace SF2::Entity::Modulator;

@interface EntityModulatorSourceTests : XCTestCase
@end

@implementation EntityModulatorSourceTests

- (void)setUp {
}

- (void)tearDown {
}

- (void)testValidity {
  Source s;
  XCTAssertTrue(s.isValid());
  XCTAssertTrue(s.isUnipolar());
  XCTAssertTrue(s.isPositive());
  XCTAssertEqual(Source::ContinuityType::linear, s.type());
  XCTAssertEqual("linear", s.continuityTypeName());
  
  XCTAssertFalse(s.isContinuousController());
  XCTAssertFalse(s.isBipolar());
  XCTAssertFalse(s.isNegative());
}

- (void)testLinear {
  Source s{Source(Source::GeneralIndex::none).linear()};
  XCTAssertTrue(s.isValid());
  XCTAssertTrue(s.isUnipolar());
  XCTAssertTrue(s.isPositive());
  XCTAssertEqual(Source::ContinuityType::linear, s.type());
  XCTAssertEqual("linear", s.continuityTypeName());
}

- (void)testConcave {
  Source s{Source(Source::GeneralIndex::none).concave()};
  XCTAssertTrue(s.isValid());
  XCTAssertTrue(s.isUnipolar());
  XCTAssertTrue(s.isPositive());
  XCTAssertEqual(Source::ContinuityType::concave, s.type());
  XCTAssertEqual("concave", s.continuityTypeName());
}

- (void)testConvex {
  Source s{Source(Source::GeneralIndex::none).convex()};
  XCTAssertTrue(s.isValid());
  XCTAssertTrue(s.isUnipolar());
  XCTAssertTrue(s.isPositive());
  XCTAssertEqual(Source::ContinuityType::convex, s.type());
  XCTAssertEqual("convex", s.continuityTypeName());
}

- (void)testSwitched {
  Source s{Source(Source::GeneralIndex::none).switched()};
  XCTAssertTrue(s.isValid());
  XCTAssertTrue(s.isUnipolar());
  XCTAssertTrue(s.isPositive());
  XCTAssertEqual(Source::ContinuityType::switched, s.type());
  XCTAssertEqual("switched", s.continuityTypeName());
}

- (void)testGeneralIndices {
  for (auto bits : {0, 2, 3, 10, 13, 14, 16, 127}) {
    Source s{Source(Source::GeneralIndex(bits))};
    XCTAssertTrue(s.isValid());
    XCTAssertFalse(s.isContinuousController());
    XCTAssertEqual(Source::GeneralIndex(bits), s.generalIndex());
  }
  
  for (auto bits : {1, 4, 5, 11, 126}) {
    Source s{Source(Source::GeneralIndex(bits))};
    XCTAssertFalse(s.isValid());
    XCTAssertFalse(s.isContinuousController());
  }
}

- (void)testContinuousIndices {
  for (auto bits : {1, 2, 3, 4, 31, 64, 97, 119}) {
    Source s{Source(Source::CC(bits))};
    XCTAssertTrue(s.isValid());
    XCTAssertTrue(s.isContinuousController());
    XCTAssertEqual(bits, s.ccIndex().value);
  }
  
  for (auto bits : {0, 6, 32, 63, 98, 101, 120, 127}) {
    Source s{Source(Source::CC(bits))};
    XCTAssertFalse(s.isValid());
    XCTAssertTrue(s.isContinuousController());
  }
}

- (void)testDirection {
  Source s{Source(Source::GeneralIndex::none)};
  XCTAssertTrue(s.isPositive());
  XCTAssertFalse(s.isNegative());
  s = Source(Source::GeneralIndex::none).negative();
  XCTAssertFalse(s.isPositive());
  XCTAssertTrue(s.isNegative());
}


- (void)testPolarity {
  Source s{Source(Source::GeneralIndex::none)};
  XCTAssertTrue(s.isUnipolar());
  XCTAssertFalse(s.isBipolar());
  s = s.bipolar();
  XCTAssertFalse(s.isUnipolar());
  XCTAssertTrue(s.isBipolar());
}

- (void)testBuilderBasic {
  Source s0{Source::GeneralIndex::noteOnVelocity};
  XCTAssertEqual(s0.generalIndex(), Source::GeneralIndex::noteOnVelocity);
  XCTAssertTrue(s0.isPositive());
  XCTAssertTrue(s0.isUnipolar());
  XCTAssertEqual(s0.type(), Source::ContinuityType::linear);
}

- (void)testBuilderNone {
  Source s0{Source::GeneralIndex::none};
  XCTAssertEqual(s0.generalIndex(), Source::GeneralIndex::none);
}

- (void)testBuilderGeneralPositiveUnipolarLinear {
  Source s0{Source(Source::GeneralIndex::noteOnVelocity).positive().unipolar().linear()};
  XCTAssertEqual(s0.generalIndex(), Source::GeneralIndex::noteOnVelocity);
  XCTAssertTrue(s0.isPositive());
  XCTAssertTrue(s0.isUnipolar());
  XCTAssertEqual(s0.type(), Source::ContinuityType::linear);
}

- (void)testBuilderGeneralNegativeUnipolarLinear {
  Source s0{Source(Source::GeneralIndex::noteOnVelocity).negative().unipolar().linear()};
  XCTAssertEqual(s0.generalIndex(), Source::GeneralIndex::noteOnVelocity);
  XCTAssertTrue(s0.isNegative());
  XCTAssertTrue(s0.isUnipolar());
  XCTAssertEqual(s0.type(), Source::ContinuityType::linear);
}

- (void)testBuilderGeneralPositiveBipolarLinear {
  Source s0{Source(Source::GeneralIndex::noteOnVelocity).negative().bipolar().linear()};
  XCTAssertEqual(s0.generalIndex(), Source::GeneralIndex::noteOnVelocity);
  XCTAssertTrue(s0.isNegative());
  XCTAssertTrue(s0.isBipolar());
  XCTAssertEqual(s0.type(), Source::ContinuityType::linear);
}

- (void)testBuilderGeneralPositiveBipolarConcave {
  Source s0{Source(Source::GeneralIndex::noteOnVelocity).negative().bipolar().concave()};
  XCTAssertEqual(s0.generalIndex(), Source::GeneralIndex::noteOnVelocity);
  XCTAssertTrue(s0.isNegative());
  XCTAssertTrue(s0.isBipolar());
  XCTAssertEqual(s0.type(), Source::ContinuityType::concave);
}

- (void)testBuilderGeneralPositiveBipolarConvex {
  Source s0{Source(Source::GeneralIndex::noteOnVelocity).negative().bipolar().convex()};
  XCTAssertEqual(s0.generalIndex(), Source::GeneralIndex::noteOnVelocity);
  XCTAssertTrue(s0.isNegative());
  XCTAssertTrue(s0.isBipolar());
  XCTAssertEqual(s0.type(), Source::ContinuityType::convex);
}

- (void)testFlippingDirection {
  Source s0{Source(Source::GeneralIndex::noteOnVelocity).positive().negative().positive().convex()};
  XCTAssertTrue(s0.isPositive());
}

- (void)testFlippingPolarity {
  Source s0{Source(Source::GeneralIndex::noteOnVelocity).unipolar().bipolar().unipolar().convex()};
  XCTAssertTrue(s0.isUnipolar());
}

- (void)testChangingContinuity {
  Source s0{Source(Source::GeneralIndex::noteOnVelocity).unipolar().linear().switched()};
  XCTAssertEqual(s0.type(), Source::ContinuityType::switched);
}

- (void)testDescription {
  auto s = Source(Source::GeneralIndex::none);
  XCTAssertEqual(s.description(), "none(uni/-+/linear)");
  s = Source(Source::GeneralIndex::none).concave();
  XCTAssertEqual(s.description(), "none(uni/-+/concave)");
  s = Source(Source::GeneralIndex::none).convex();
  XCTAssertEqual(s.description(), "none(uni/-+/convex)");
  s = Source(Source::GeneralIndex::none).negative();
  XCTAssertEqual(s.description(), "none(uni/+-/linear)");
  s = Source(Source::GeneralIndex::none).bipolar();
  XCTAssertEqual(s.description(), "none(bi/-+/linear)");

  s = Source(Source::GeneralIndex::noteOnVelocity);
  XCTAssertEqual(s.description(), "velocity(uni/-+/linear)");
  s = Source(Source::GeneralIndex::noteOnKey);
  XCTAssertEqual(s.description(), "key(uni/-+/linear)");
  s = Source(Source::GeneralIndex::keyPressure);
  XCTAssertEqual(s.description(), "keyPressure(uni/-+/linear)");
  s = Source(Source::GeneralIndex::channelPressure);
  XCTAssertEqual(s.description(), "channelPressure(uni/-+/linear)");
  s = Source(Source::GeneralIndex::pitchWheel);
  XCTAssertEqual(s.description(), "pitchWheel(uni/-+/linear)");
  s = Source(Source::GeneralIndex::pitchWheelSensitivity);
  XCTAssertEqual(s.description(), "pitchWheelSensitivity(uni/-+/linear)");
  s = Source(Source::CC(1));
  XCTAssertEqual(s.description(), "CC[1](uni/-+/linear)");
}
@end
