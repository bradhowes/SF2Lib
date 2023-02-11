#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include "../SampleBasedContexts.hpp"

#include "SF2Lib/IO/Parser.hpp"

@interface ParserTests : XCTestCase

@end

@implementation ParserTests {
  SampleBasedContexts contexts;
}

- (void)testParsing1 {
  auto url = contexts.context0.url();
  auto parser{SF2::IO::Parser::parse(url.path.UTF8String)};
  XCTAssertEqual(235, parser.presets.size());
  std::cout << parser.embeddedName << '\n';
  XCTAssertEqual("Free Font GM Ver. 3.2", parser.embeddedName);
}

- (void)testParsing2 {
  auto url = contexts.context1.url();
  auto parser{SF2::IO::Parser::parse(url.path.UTF8String)};
  XCTAssertEqual(270, parser.presets.size());
  std::cout << parser.embeddedName << '\n';
  XCTAssertEqual("GeneralUser GS MuseScore version 1.442", parser.embeddedName);
}

- (void)testParsing3 {
  auto url = contexts.context2.url();
  auto parser{SF2::IO::Parser::parse(url.path.UTF8String)};
  XCTAssertEqual(1, parser.presets.size());
  std::cout << parser.embeddedName << '\n';
  XCTAssertEqual("User Bank", parser.embeddedName);
}

@end
