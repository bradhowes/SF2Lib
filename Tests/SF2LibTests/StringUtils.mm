#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "SF2Lib/Utils/StringUtils.hpp"

@interface StringUtilsTests : XCTestCase

@end

@implementation StringUtilsTests

- (void)testTrimPropertyHandlesEmptyString {
  std::string data{""};
  SF2::Utils::trim_property(data);
  XCTAssertEqual("", data);
}

- (void)testTrimPropertyHandlesAllWhitespaces {
  std::string data{"  \t \t   \t "};
  SF2::Utils::trim_property(data);
  XCTAssertEqual("", data);
}

- (void)testTrimPropertyHandlesAllWhitespacesWithEmbeddedNull {
  std::string data{"  \t \t \0  \t "};
  SF2::Utils::trim_property(data);
  XCTAssertEqual("", data);
}

- (void)testTrimPropertyTrimsEnds {
  auto data = std::string{"  this is a test \0 "};
  SF2::Utils::trim_property(data);
  XCTAssertEqual("this is a test", data);
}

- (void)testTrimPropertyWithFixedArray {
  char data[32]{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  memcpy(data, "  this is a test  \0  \0 ", 23);
  SF2::Utils::trim_property(data);
  XCTAssertEqual("this is a test", std::string(data));
}

@end
