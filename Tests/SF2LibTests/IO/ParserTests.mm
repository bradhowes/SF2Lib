#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#include "../SampleBasedContexts.hpp"

#include "SF2Lib/IO/Parser.hpp"
#include "SF2Lib/IO/Tag.hpp"

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

- (void)testBadSize {
  NSURL* tmp = [[NSURL fileURLWithPath: NSTemporaryDirectory() isDirectory:YES]
                URLByAppendingPathComponent: [[NSUUID UUID] UUIDString]];

  uint32_t riff = ('F' << 24) | ('F' << 16) | ('I' << 8) | 'R';
  XCTAssertEqual(1179011410, riff);
  ++riff;

  uint32_t sfbk = ('k' << 24) | ('b' << 16) | ('f' << 8) | 's';
  XCTAssertEqual(1801610867, sfbk);

  NSMutableData* data = [NSMutableData dataWithCapacity: 8];
  [data appendBytes:&riff length:sizeof(riff) - 1];
  // [data appendBytes:&sfbk length:sizeof(sfbk)];

  XCTAssertTrue([data writeToURL:tmp atomically:NO]);

  XCTAssertEqual(SF2::IO::File(tmp.path.UTF8String).load(), SF2::IO::File::LoadResponse::invalidFormat);
}

- (void)testNoRiffPayload {
  NSURL* tmp = [[NSURL fileURLWithPath: NSTemporaryDirectory() isDirectory:YES]
                URLByAppendingPathComponent: [[NSUUID UUID] UUIDString]];

  uint32_t riff = ('F' << 24) | ('F' << 16) | ('I' << 8) | 'R';
  XCTAssertEqual(1179011410, riff);
  ++riff;

  uint32_t sfbk = ('k' << 24) | ('b' << 16) | ('f' << 8) | 's';
  XCTAssertEqual(1801610867, sfbk);

  NSMutableData* data = [NSMutableData dataWithCapacity: 8];
  [data appendBytes:&riff length:sizeof(riff)];
  [data appendBytes:&sfbk length:sizeof(sfbk)];
  [data appendBytes:&sfbk length:sizeof(sfbk)];

  XCTAssertTrue([data writeToURL:tmp atomically:NO]);

  XCTAssertEqual(SF2::IO::File(tmp.path.UTF8String).load(), SF2::IO::File::LoadResponse::invalidFormat);
}

- (void)testBadSfbkPayload {
  NSURL* tmp = [[NSURL fileURLWithPath: NSTemporaryDirectory() isDirectory:YES]
                URLByAppendingPathComponent: [[NSUUID UUID] UUIDString]];

  uint32_t riff = SF2::IO::Tag(SF2::IO::Tags::riff).rawValue();
  uint32_t sfbk = SF2::IO::Tag(SF2::IO::Tags::sfbk).rawValue();
  uint32_t list = SF2::IO::Tag(SF2::IO::Tags::list).rawValue();
  uint32_t sdta = SF2::IO::Tag(SF2::IO::Tags::sdta).rawValue();
  uint32_t pdta = SF2::IO::Tag(SF2::IO::Tags::pdta).rawValue();
  uint32_t size = 8;
  NSMutableData* data = [NSMutableData dataWithCapacity: 8];
  [data appendBytes:&riff length:sizeof(riff)];
  [data appendBytes:&size length:sizeof(size)];
  [data appendBytes:&sfbk length:sizeof(sfbk)];
  [data appendBytes:&list length:sizeof(list)];
  [data appendBytes:&size length:sizeof(size)];
  [data appendBytes:&sdta length:sizeof(sdta)];
  [data appendBytes:&list length:sizeof(list)];
  [data appendBytes:&size length:sizeof(size)];
  [data appendBytes:&pdta length:sizeof(pdta)];

  XCTAssertTrue([data writeToURL:tmp atomically:YES]);

  XCTAssertEqual(SF2::IO::File(tmp.path.UTF8String).load(), SF2::IO::File::LoadResponse::invalidFormat);
}

@end
