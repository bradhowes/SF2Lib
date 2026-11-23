// Copyright © 2026 Brad Howes. All rights reserved.

#include <sstream>

#include <XCTest/XCTest.h>

#include "SF2File/Entity/Modulator/Modulator.hpp"

using namespace SF2::Entity::Modulator;
using Index = SF2::Entity::Generator::Index;

@interface EntityModulatorTransformTests : XCTestCase
@end

@implementation EntityModulatorTransformTests

- (void)testLinear {
  Transformer transformer;
  XCTAssertTrue(transformer.isValid());
  XCTAssertEqual(Transformer::Kind::linear, transformer.kind());
  XCTAssertEqual(-12.5, transformer.transform(-12.5));
  XCTAssertEqual(12.5, transformer.transform(12.5));
}

- (void)testAbsolute {
  // SF2.04 8.3: transform 2 is "absolute value".
  Transformer transformer{Transformer::Kind::absolute};
  XCTAssertTrue(transformer.isValid());
  XCTAssertEqual(2, transformer.bits());
  XCTAssertEqual(12.5, transformer.transform(-12.5));
  XCTAssertEqual(12.5, transformer.transform(12.5));
  XCTAssertEqual(0.0, transformer.transform(0.0));
}

- (void)testUnknownKindsAreInvalid {
  for (uint16_t bits : {uint16_t(1), uint16_t(3), uint16_t(0x8000), uint16_t(0xFFFF)}) {
    Transformer transformer{Transformer::Kind(bits)};
    XCTAssertFalse(transformer.isValid(), @"bits %d", bits);
    std::ostringstream os;
    os << transformer;
    XCTAssertEqual("unknown(" + std::to_string(bits) + ")", os.str());
  }
}

- (void)testIdentityIncludesTransform {
  // SF2.01 9.5.1: identical means the same source, destination, amount source and transform. 7.4's duplicate rule within
  // a zone only uses the first three.
  Source cc16{Source(Source::CC(16))};
  Modulator linear{cc16, Index::initialAttenuation, 100};
  Modulator otherAmount{cc16, Index::initialAttenuation, 500};
  Modulator absolute{cc16, Index::initialAttenuation, 100, Source(), Transformer(Transformer::Kind::absolute)};

  XCTAssertTrue(linear == otherAmount);
  XCTAssertFalse(linear == absolute);
  XCTAssertTrue(linear != absolute);
  XCTAssertTrue(linear.hasSameEnumerators(absolute));
  XCTAssertFalse(linear.hasSameEnumerators(Modulator{cc16, Index::pan, 100}));
}

@end
