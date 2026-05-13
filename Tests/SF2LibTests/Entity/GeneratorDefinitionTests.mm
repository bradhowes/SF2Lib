// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SF2File/Entity/Generator/Definition.hpp"

using namespace SF2::Entity::Generator;

@interface GeneratorDefinitionTests : XCTestCase
@end

@implementation GeneratorDefinitionTests

- (void)testConvertedValueOf {
  auto def1 = Definition("test1", Definition::ValueKind::coarseOffset, Definition::ValueRange(-1234, 1000), true, Definition::NRPNMultiplier::x1);
  def1.dump(Amount(123));
  auto def2 = Definition("test2", Definition::ValueKind::offset, Definition::ValueRange(-1234, 1000), true, Definition::NRPNMultiplier::x1);
  def2.dump(Amount(456));
  auto def3 = Definition("test3", Definition::ValueKind::UNUSED, Definition::ValueRange(-1234, 1000), true, Definition::NRPNMultiplier::x1);
  def3.dump(Amount(456));
}
@end
