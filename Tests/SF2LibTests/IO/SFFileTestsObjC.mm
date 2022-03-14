// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "../SampleBasedContexts.hpp"

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Voice/Sample/NormalizedSampleSource.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Voice::Sample;

@interface SFFileTestsObjC : XCTestCase

@end

@implementation SFFileTestsObjC {
  SampleBasedContexts* contexts;
}

- (void)setUp {
  contexts = new SampleBasedContexts;
}

- (void)tearDown {
  delete contexts;
}

- (void)testParsing1 {
  const auto& file = contexts->context0.file();

  XCTAssertEqual(235, file.presets().size());
  XCTAssertEqual(235, file.presetZones().size());
  XCTAssertEqual(705, file.presetZoneGenerators().size());
  XCTAssertEqual(0, file.presetZoneModulators().size());
  XCTAssertEqual(235, file.instruments().size());
  XCTAssertEqual(1498, file.instrumentZones().size());
  XCTAssertEqual(26537, file.instrumentZoneGenerators().size());
  XCTAssertEqual(0, file.instrumentZoneModulators().size());
  XCTAssertEqual(495, file.sampleHeaders().size());
}

- (void)testParsing2 {
  const auto& file = contexts->context1.file();

  XCTAssertEqual(270, file.presets().size());
  XCTAssertEqual(2616, file.presetZones().size());
  XCTAssertEqual(17936, file.presetZoneGenerators().size());
  XCTAssertEqual(363, file.presetZoneModulators().size());
  XCTAssertEqual(310, file.instruments().size());
  XCTAssertEqual(2165, file.instrumentZones().size());
  XCTAssertEqual(18942, file.instrumentZoneGenerators().size());
  XCTAssertEqual(2151, file.instrumentZoneModulators().size());
  XCTAssertEqual(864, file.sampleHeaders().size());
}

- (void)testParsing3 {
  const auto& file = contexts->context2.file();

  XCTAssertEqual(1, file.presets().size());
  XCTAssertEqual(6, file.presetZones().size());
  XCTAssertEqual(12, file.presetZoneGenerators().size());
  XCTAssertEqual(0, file.presetZoneModulators().size());
  XCTAssertEqual(6, file.instruments().size());
  XCTAssertEqual(150, file.instrumentZones().size());
  XCTAssertEqual(443, file.instrumentZoneGenerators().size());
  XCTAssertEqual(0, file.instrumentZoneModulators().size());
  XCTAssertEqual(24, file.sampleHeaders().size());

  auto samples = file.sampleSourceCollection()[0];
  samples.load();
  XCTAssertEqual(samples.size(), 115504);

  XCTAssertEqualWithAccuracy(samples[0], -0.00103759765625, 0.000001);
}

- (void)testSamples {
  const auto& file = contexts->context2.file();
  auto samples = file.sampleSourceCollection()[0];
  samples.load();

  Float epsilon = 1e-6;

  off_t sampleOffset = 246;
  XCTAssertEqual(samples.size(), 115504);
  XCTAssertEqualWithAccuracy(samples[0], -0.00103759765625, epsilon);

  int fd = contexts->context2.fd();
  off_t pos = ::lseek(fd, sampleOffset, SEEK_SET);
  XCTAssertEqual(pos, sampleOffset);

  int16_t rawSamples[4];
  ::read(fd, &rawSamples, sizeof(rawSamples));

  XCTAssertEqualWithAccuracy(rawSamples[0] * NormalizedSampleSource::normalizationScale, samples[0], epsilon);
  XCTAssertEqualWithAccuracy(rawSamples[1] * NormalizedSampleSource::normalizationScale, samples[1], epsilon);
  XCTAssertEqualWithAccuracy(rawSamples[2] * NormalizedSampleSource::normalizationScale, samples[2], epsilon);
  XCTAssertEqualWithAccuracy(rawSamples[3] * NormalizedSampleSource::normalizationScale, samples[3], epsilon);

  file.dumpThreaded();
}

- (void)testDump {
  const auto& file = contexts->context0.file();
  XCTAssertNoThrow(file.dump());
}

@end
