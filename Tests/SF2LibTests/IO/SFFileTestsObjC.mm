// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "TestResources.hpp"

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Voice/Sample/NormalizedSampleSource.hpp"

using namespace SF2;
using namespace SF2::Render;
using namespace SF2::Render::Voice::Sample;

@interface SFFileTestsObjC : XCTestCase

@end

@implementation SFFileTestsObjC {
  SampleBasedContexts* contexts;
  Float epsilon;
}

- (void)setUp {
  contexts = new SampleBasedContexts;
  epsilon = PresetTestContextBase::epsilonValue();
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

  XCTAssertEqual(235, file.presetIndicesOrderedByBankProgram().size());
  XCTAssertEqual(7, file.presetIndicesOrderedByBankProgram()[3]);
  XCTAssertEqual(std::string("Honky-tonk"), file.presets()[7].name());
  XCTAssertEqual(176, file.presetIndicesOrderedByBankProgram()[200]);
  XCTAssertEqual(std::string("Castanets"), file.presets()[176].name());
  XCTAssertEqual(234, file.presetIndicesOrderedByBankProgram()[file.presets().size() - 1]);
  XCTAssertEqual(std::string("SFX"), file.presets()[234].name());

  file.presets()[80].dump("", 80);
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

  XCTAssertEqual(270, file.presetIndicesOrderedByBankProgram().size());
  XCTAssertEqual(81, file.presetIndicesOrderedByBankProgram()[3]);
  XCTAssertEqual(std::string("Honky-Tonk"), file.presets()[81].name());
  XCTAssertEqual(117, file.presetIndicesOrderedByBankProgram()[200]);
  XCTAssertEqual(std::string("Melodic Tom 2"), file.presets()[117].name());
  XCTAssertEqual(69, file.presetIndicesOrderedByBankProgram()[file.presets().size() - 1]);
  XCTAssertEqual(std::string("SFX"), file.presets()[69].name());
  // file.presets()[69].dump("", 69);
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

  XCTAssertEqual(1, file.presetIndicesOrderedByBankProgram().size());
  XCTAssertEqual(0, file.presetIndicesOrderedByBankProgram()[0]);
  XCTAssertEqual(std::string("Nice Piano"), file.presets()[0].name());
  // file.presets()[0].dump("", 0);

  auto samples = file.sampleSourceCollection()[0];
  XCTAssertEqual(samples.size(), 115504);

  XCTAssertEqualWithAccuracy(samples[0], -0.00103759765625, 0.000001);
}

- (void)testSamples {
  const auto& file = contexts->context2.file();
  auto samples = file.sampleSourceCollection()[0];

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

  // file.dumpThreaded();
}

- (void)testDump0 {
  const auto& file = contexts->context0.file();
  XCTAssertNoThrow(file.dump());
  XCTAssertNoThrow(file.dumpThreaded());
}

- (void)testDump1 {
  const auto& file = contexts->context1.file();
  XCTAssertNoThrow(file.dump());
  XCTAssertNoThrow(file.dumpThreaded());
}

- (void)testLoad {
  XCTAssertEqual(SF2::IO::File("/dev/null").load(), SF2::IO::File::LoadResponse::invalidFormat);
  XCTAssertEqual(SF2::IO::File("/dev/zero").load(), SF2::IO::File::LoadResponse::invalidFormat);
  XCTAssertEqual(SF2::IO::File("/dev/urandom").load(), SF2::IO::File::LoadResponse::invalidFormat);
  NSURL* b1 = [TestResources getBadResourceUrl:0];
  XCTAssertNotEqual(SF2::IO::File([[b1 absoluteString] UTF8String]).load(), SF2::IO::File::LoadResponse::ok);
  NSURL* b2 = [TestResources getBadResourceUrl:1];
  XCTAssertNotEqual(SF2::IO::File([[b2 absoluteString] UTF8String]).load(), SF2::IO::File::LoadResponse::ok);
}
@end
