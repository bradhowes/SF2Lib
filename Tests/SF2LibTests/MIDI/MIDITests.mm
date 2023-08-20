// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SF2Lib/Types.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

using namespace SF2;
using namespace SF2::MIDI;

@interface MIDITests : XCTestCase {
  Float epsilon;
}
@end

//@implementation MIDITests
//
//- (void)setUp {
//  epsilon = 0.0000001;
//}
//
//@end
