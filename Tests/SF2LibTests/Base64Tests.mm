#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "SF2Lib/Utils/Base64.hpp"

@interface Base64Tests : XCTestCase

@end

@implementation Base64Tests

- (void)testRoundTrip {
  std::string data{"/This/is a test/of the emergency/broadcasting/system.sf2"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  // std::cout << "encoded: " << encoded << '\n';
  std::string decoded = SF2::Utils::Base64::decode(encoded);
  // std::cout << "decoded: " << decoded << '\n';
  XCTAssertEqual(data, decoded);
}

- (void)testIdiom {
  std::string data{"Many hands make light work."};
  std::string encoded = SF2::Utils::Base64::encode(data);
  // std::cout << "encoded: " << encoded << '\n';
  XCTAssertEqual(encoded, "TWFueSBoYW5kcyBtYWtlIGxpZ2h0IHdvcmsu");
  std::string decoded = SF2::Utils::Base64::decode(encoded);
  // std::cout << "decoded: " << decoded << '\n';
  XCTAssertEqual(data, decoded);
}

- (void)testEmptyString {
  std::string data{""};
  std::string encoded = SF2::Utils::Base64::encode(data);
  // std::cout << "encoded: " << encoded << '\n';
  std::string decoded = SF2::Utils::Base64::decode(encoded);
  // std::cout << "decoded: " << decoded << '\n';
  XCTAssertEqual(data, decoded);
}

- (void)testOneCharString {
  std::string data{"A"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  // std::cout << "encoded: " << encoded << '\n';
  std::string decoded = SF2::Utils::Base64::decode(encoded);
  // std::cout << "decoded: " << decoded << '\n';
  XCTAssertEqual(data, decoded);
}

- (void)testTwoCharString {
  std::string data{"AB"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  // std::cout << "encoded: " << encoded << '\n';
  std::string decoded = SF2::Utils::Base64::decode(encoded);
  // std::cout << "decoded: " << decoded << '\n';
  XCTAssertEqual(data, decoded);
}

- (void)testThreeCharString {
  std::string data{"ABc"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  // std::cout << "encoded: " << encoded << '\n';
  std::string decoded = SF2::Utils::Base64::decode(encoded);
  // std::cout << "decoded: " << decoded << '\n';
  XCTAssertEqual(data, decoded);
}

- (void)testFourCharString {
  std::string data{"ABcd"};
  std::string encoded = SF2::Utils::Base64::encode(data);
  // std::cout << "encoded: " << encoded << '\n';
  std::string decoded = SF2::Utils::Base64::decode(encoded);
  // std::cout << "decoded: " << decoded << '\n';
  XCTAssertEqual(data, decoded);
}

- (void)testPadding {
  XCTAssertEqual(SF2::Utils::Base64::encode("light work."), "bGlnaHQgd29yay4=");
  XCTAssertEqual(SF2::Utils::Base64::encode("light work"), "bGlnaHQgd29yaw==");
  XCTAssertEqual(SF2::Utils::Base64::encode("light wor"), "bGlnaHQgd29y");
  XCTAssertEqual(SF2::Utils::Base64::encode("light wo"), "bGlnaHQgd28=");
  XCTAssertEqual(SF2::Utils::Base64::encode("light w"), "bGlnaHQgdw==");
}

@end
