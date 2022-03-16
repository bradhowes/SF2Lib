// Copyright © 2021 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>
#include <cmath>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/ConstMath.hpp"

using namespace SF2;

@interface ConstMathTests : XCTestCase
@end

@implementation ConstMathTests {
  SF2::Float epsilon;
}

- (void)setUp {
  epsilon = 1.0e-9; // 0.0000001;
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testSquared {
  XCTAssertEqualWithAccuracy(3.5 * 3.5, ConstMath::squared(3.5), epsilon);
}

- (void)testNormalizeRadians {
  double theta = 1.23 + 4 * ConstMath::Constants<double>::PI;
  XCTAssertEqualWithAccuracy(1.23, ConstMath::detail::normalizedRadians(theta), epsilon);
  theta = -ConstMath::Constants<double>::PI;
  XCTAssertEqualWithAccuracy(-theta, ConstMath::detail::normalizedRadians(theta), epsilon);
  theta = ConstMath::Constants<double>::PI;
  XCTAssertEqualWithAccuracy(theta, ConstMath::detail::normalizedRadians(theta), epsilon);
}

- (void)testSin {
  for (int index = -3600; index < 3600; index += 1) {
    double theta = index / 10.0 * ConstMath::Constants<double>::PI / 180.0;
    XCTAssertEqualWithAccuracy(std::sin(theta), ConstMath::sin(theta), epsilon);
  }
}

- (void)testCos {
  for (int index = -3600; index < 3600; index += 1) {
    double theta = index / 10.0 * ConstMath::Constants<double>::PI / 180.0;
    XCTAssertEqualWithAccuracy(std::cos(theta), ConstMath::cos(theta), epsilon);
  }
}

- (void)testAbs {
  XCTAssertEqualWithAccuracy(0.0, ConstMath::abs(0.0), epsilon);
  XCTAssertEqualWithAccuracy(1.0, ConstMath::abs(1.0), epsilon);
  XCTAssertEqualWithAccuracy(1.0, ConstMath::abs(-1.0), epsilon);
}

- (void)testPow {
  XCTAssertEqualWithAccuracy(2.5 * 2.5 * 2.5 * 2.5, ConstMath::pow(2.5, 4), epsilon);
  XCTAssertEqualWithAccuracy(2.5 * 2.5 * 2.5 * 2.5, ConstMath::pow(-2.5, 4), epsilon);
  XCTAssertEqualWithAccuracy(-2.5 * 2.5 * 2.5, ConstMath::pow(-2.5, 3), epsilon);
  XCTAssertEqualWithAccuracy(1.0, ConstMath::pow(123, 0), epsilon);
  XCTAssertEqualWithAccuracy(1.0, ConstMath::pow(123, 0), epsilon);
}

- (void)testIsEven {
  XCTAssertTrue(ConstMath::is_even(0));
  XCTAssertTrue(ConstMath::is_even(2));
  XCTAssertTrue(ConstMath::is_even(-2));

  XCTAssertFalse(ConstMath::is_even(1));
  XCTAssertFalse(ConstMath::is_even(3));
  XCTAssertFalse(ConstMath::is_even(-1));
}

- (void)testExp {
  XCTAssertEqualWithAccuracy(std::exp(2.345), ConstMath::exp(2.345), epsilon);
  XCTAssertEqualWithAccuracy(std::exp(0.0), ConstMath::exp(0.0), epsilon);
  XCTAssertEqualWithAccuracy(std::exp(-1.2), ConstMath::exp(-1.2), epsilon);
}

@end
