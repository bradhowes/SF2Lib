#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "SF2Lib/Utils/Base64.hpp"

@interface Base64Tests : XCTestCase

@end

@implementation Base64Tests

- (void)testBasic {
  std::string data{"/This/is a test/of the emergency/broadcasting/system.sf2"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  std::cout << "encoded: " << encoded << '\n';
  std::string decoded = SF2::Utils::Base64::decode(encoded);
  std::cout << "decoded: " << decoded << '\n';
  XCTAssertEqual(data, decoded);
}

@end
