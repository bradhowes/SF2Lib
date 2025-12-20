// Copyright © 2021 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>
#include <vector>

#include "SampleBasedContexts.hpp"

#include "SF2Util/Types.hpp"
#include "SF2File/IO/NormalizedSampleSource.hpp"

#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Envelope/Generator.hpp"
#include "SF2Lib/Render/LFO.hpp"
#include "SF2Lib/Render/Voice/Sample/Generator.hpp"

using namespace SF2::IO;
using namespace SF2::Render;
using namespace SF2::Render::Envelope;
using namespace SF2::Render::Voice;
using namespace SF2::Render::Voice::Sample;

@interface NormalizedSampleSourceTests : XCTestCase

@property (nonatomic) SampleBasedContexts* contexts;
@property (assign, nonatomic) SF2::Float epsilon;

@end

@implementation NormalizedSampleSourceTests

@synthesize contexts;
@synthesize epsilon;

static SF2::Entity::SampleHeader header{0, 6, 3, 5, 100, 69, 0}; // 0: start, 1: end, 2: loop start, 3: loop end
static SF2::MIDI::ChannelState channelState;
static SF2::SampleVector values = {1.0, -1.0, 0.5, 0.25, -0.25, -0.5, -0.6, -0.7};

- (void)setUp {
  [super setUp];
  self.contexts = new SampleBasedContexts;
  self.epsilon = PresetTestContextBase::epsilonValue();
}

- (void)tearDown {
  delete self.contexts;
}

- (void)testLoad {
  NormalizedSampleSource source{values, header};
  XCTAssertEqual(source.size(), size_t(52));
  XCTAssertEqual(size_t(0), source.header().startIndex());
  XCTAssertEqual(size_t(6), source.header().endIndex());

  XCTAssertEqual(source.size(), source.header().endIndex() + NormalizedSampleSource::sizePaddingAfterEnd);
  XCTAssertEqual(source[0], values[0]);
  XCTAssertEqual(source[1], values[1]);
}

- (void)testLoadSamplesPerformance0 {
  auto& file = self.contexts->context0.file();
  auto sampleEntries = file.sampleHeaders().size();
  XCTAssertEqual(sampleEntries, size_t(495));

  [self measureBlock:^{
    for (size_t index = 0; index < sampleEntries; ++index) {
      auto _ = file.sampleSourceCollection()[index];
    }
  }];
}

- (void)testLoadSamplesPerformance1 {
  auto& file = self.contexts->context1.file();
  auto sampleEntries = file.sampleHeaders().size();
  XCTAssertEqual(sampleEntries, size_t(864));

  [self measureBlock:^{
    for (size_t index = 0; index < sampleEntries; ++index) {
      auto _ = file.sampleSourceCollection()[index];
    }
  }];
}

- (void)testLoadSamplesPerformance2 {
  auto& file = self.contexts->context2.file();
  auto sampleEntries = file.sampleHeaders().size();
  XCTAssertEqual(sampleEntries, size_t(24));

  [self measureBlock:^{
    for (size_t index = 0; index < sampleEntries; ++index) {
      auto _ = file.sampleSourceCollection()[index];
    }
  }];
}

@end
