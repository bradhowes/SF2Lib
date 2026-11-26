#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "SF2Util/Base64.hpp"

@interface Base64Tests : XCTestCase

@end

@implementation Base64Tests

- (void)testRoundTrip {
  std::string data{"/This/is a test/of the emergency/broadcasting/system.sf2"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  auto decoded = SF2::Utils::Base64::decode(encoded);
  XCTAssertTrue(decoded.has_value());
  XCTAssertEqual(data, std::string({reinterpret_cast<const char*>(decoded.value().data()), decoded.value().size()}));
}

- (void)testIdiom {
  std::string data{"Many hands make light work."};
  std::string encoded = SF2::Utils::Base64::encode(data);
  XCTAssertEqual(encoded, "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsu");
  auto decoded = SF2::Utils::Base64::decode(encoded);
  XCTAssertTrue(decoded.has_value());
  XCTAssertEqual(data, std::string({reinterpret_cast<const char*>(decoded.value().data()), decoded.value().size()}));
}

- (void)testEmptyString {
  std::string data{""};
  std::string encoded = SF2::Utils::Base64::encode(data);
  auto decoded = SF2::Utils::Base64::decode(encoded);
  XCTAssertTrue(decoded.has_value());
  XCTAssertEqual(data, std::string({reinterpret_cast<const char*>(decoded.value().data()), decoded.value().size()}));
}

- (void)testOneCharString {
  std::string data{"A"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  auto decoded = SF2::Utils::Base64::decode(encoded);
  XCTAssertTrue(decoded.has_value());
  XCTAssertEqual(data, std::string({reinterpret_cast<const char*>(decoded.value().data()), decoded.value().size()}));
}

- (void)testTwoCharString {
  std::string data{"AB"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  auto decoded = SF2::Utils::Base64::decode(encoded);
  XCTAssertTrue(decoded.has_value());
  XCTAssertEqual(data, std::string({reinterpret_cast<const char*>(decoded.value().data()), decoded.value().size()}));
}

- (void)testThreeCharString {
  std::string data{"ABc"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  auto decoded = SF2::Utils::Base64::decode(encoded);
  XCTAssertTrue(decoded.has_value());
  XCTAssertEqual(data, std::string({reinterpret_cast<const char*>(decoded.value().data()), decoded.value().size()}));
}

- (void)testFourCharString {
  std::string data{"ABcd"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  auto decoded = SF2::Utils::Base64::decode(encoded);
  XCTAssertTrue(decoded.has_value());
  XCTAssertEqual(data, std::string({reinterpret_cast<const char*>(decoded.value().data()), decoded.value().size()}));
}

- (void)testPadding {
  XCTAssertEqual(SF2::Utils::Base64::encode("light work."), "bGlnaHQgd29yay4=");
  XCTAssertEqual(SF2::Utils::Base64::encode("light work"), "bGlnaHQgd29yaw==");
  XCTAssertEqual(SF2::Utils::Base64::encode("light wor"), "bGlnaHQgd29y");
  XCTAssertEqual(SF2::Utils::Base64::encode("light wo"), "bGlnaHQgd28=");
  XCTAssertEqual(SF2::Utils::Base64::encode("light w"), "bGlnaHQgdw==");
}

@end
