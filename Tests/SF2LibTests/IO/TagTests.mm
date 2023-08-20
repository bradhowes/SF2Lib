// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SF2Lib/IO/Tag.hpp"

using namespace SF2::IO;

@interface TagsTests : XCTestCase
@end

@implementation TagsTests

- (void)testPack4Chars {
  uint32_t value = Pack4Chars("abcd");
  XCTAssertEqual(1684234849, value);
}

- (void)testRiff {
  XCTAssertEqual(1179011410, static_cast<uint32_t>(Tags::riff));
}

/**
 Generate partial soundfont file contents and try to process them to make sure that there are no BAD_ACCESS
 exceptions.
 */
//func testRobustnessWithPartialPayload() {
//  let tmp = newTempFileURL
//  defer { try? FileManager.default.removeItem(at: tmp) }
//
//  guard let original = try? Data(contentsOf: urls[0]) else { fatalError() }
//  for _ in 0..<20 {
//    let truncatedCount = Int.random(in: 1..<(original.count / 2))
//    let data = original.subdata(in: 0..<truncatedCount)
//    do {
//      try data.write(to: tmp, options: .atomic)
//    } catch _ as NSError {
//      fatalError()
//    }
//    let result = SoundFontInfo.load(viaParser: tmp)
//    XCTAssertNil(result)
//  }
//}

@end
