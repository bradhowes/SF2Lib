#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "SF2Lib.hpp"

@interface SF2LibTests : XCTestCase

@end

@implementation SF2LibTests

- (void)testConstruction {
  auto engine = SF2::Engine(48000.0, 48);
}

@end
