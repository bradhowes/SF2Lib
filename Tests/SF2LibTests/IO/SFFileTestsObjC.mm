// Copyright © 2020 Brad Howes. All rights reserved.

#include <iostream>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "TestResources.hpp"

#include "SF2File/IO/File.hpp"
// #include "SF2File/IO/NormalizedSampleSource.hpp"

using namespace SF2;
using namespace SF2::IO;
using namespace SF2::Render;
using namespace SF2::Render::Voice::Sample;

@interface SFFileTestsObjC : XCTestCase

@property (nonatomic) SampleBasedContexts* contexts;
@property (nonatomic) Float epsilon;

@end

@implementation SFFileTestsObjC

@synthesize contexts;
@synthesize epsilon;

- (void)setUp {
  self.contexts = new SampleBasedContexts;
  self.epsilon = PresetTestContextBase::epsilonValue();
}

- (void)testParsing1 {
  const auto& file = self.contexts->context0.file();

  XCTAssertEqual(size_t(235), file.presets().size());
  XCTAssertEqual(size_t(235), file.presetZones().size());
  XCTAssertEqual(size_t(705), file.presetZoneGenerators().size());
  XCTAssertEqual(size_t(0), file.presetZoneModulators().size());
  XCTAssertEqual(size_t(235), file.instruments().size());
  XCTAssertEqual(size_t(1498), file.instrumentZones().size());
  XCTAssertEqual(size_t(26537), file.instrumentZoneGenerators().size());
  XCTAssertEqual(size_t(0), file.instrumentZoneModulators().size());
  XCTAssertEqual(size_t(495), file.sampleHeaders().size());

  XCTAssertEqual(size_t(235), file.presetIndicesOrderedByBankProgram().size());
  XCTAssertEqual(size_t(7), file.presetIndicesOrderedByBankProgram()[3]);
  XCTAssertEqual(std::string("Honky-tonk"), file.presets()[7].name());
  XCTAssertEqual(size_t(176), file.presetIndicesOrderedByBankProgram()[200]);
  XCTAssertEqual(std::string("Castanets"), file.presets()[176].name());
  XCTAssertEqual(size_t(234), file.presetIndicesOrderedByBankProgram()[file.presets().size() - 1]);
  XCTAssertEqual(std::string("SFX"), file.presets()[234].name());

  // file.presets()[80].dump("", 80);
}

- (void)testParsing2 {
  const auto& file = self.contexts->context1.file();

  XCTAssertEqual(size_t(270), file.presets().size());
  XCTAssertEqual(size_t(2616), file.presetZones().size());
  XCTAssertEqual(size_t(17936), file.presetZoneGenerators().size());
  XCTAssertEqual(size_t(363), file.presetZoneModulators().size());
  XCTAssertEqual(size_t(310), file.instruments().size());
  XCTAssertEqual(size_t(2165), file.instrumentZones().size());
  XCTAssertEqual(size_t(18942), file.instrumentZoneGenerators().size());
  XCTAssertEqual(size_t(2151), file.instrumentZoneModulators().size());
  XCTAssertEqual(size_t(864), file.sampleHeaders().size());

  XCTAssertEqual(size_t(270), file.presetIndicesOrderedByBankProgram().size());
  XCTAssertEqual(size_t(81), file.presetIndicesOrderedByBankProgram()[3]);
  XCTAssertEqual(std::string("Honky-Tonk"), file.presets()[81].name());
  XCTAssertEqual(size_t(117), file.presetIndicesOrderedByBankProgram()[200]);
  XCTAssertEqual(std::string("Melodic Tom 2"), file.presets()[117].name());
  XCTAssertEqual(size_t(69), file.presetIndicesOrderedByBankProgram()[file.presets().size() - 1]);
  XCTAssertEqual(std::string("SFX"), file.presets()[69].name());
  // file.presets()[69].dump("", 69);
}

- (void)testParsing3 {
  auto& file = self.contexts->context2.file();

  XCTAssertEqual(size_t(1), file.presets().size());
  XCTAssertEqual(size_t(6), file.presetZones().size());
  XCTAssertEqual(size_t(12), file.presetZoneGenerators().size());
  XCTAssertEqual(size_t(0), file.presetZoneModulators().size());
  XCTAssertEqual(size_t(6), file.instruments().size());
  XCTAssertEqual(size_t(150), file.instrumentZones().size());
  XCTAssertEqual(size_t(443), file.instrumentZoneGenerators().size());
  XCTAssertEqual(size_t(0), file.instrumentZoneModulators().size());
  XCTAssertEqual(size_t(24), file.sampleHeaders().size());

  XCTAssertEqual(size_t(1), file.presetIndicesOrderedByBankProgram().size());
  XCTAssertEqual(size_t(0), file.presetIndicesOrderedByBankProgram()[0]);
  XCTAssertEqual(std::string("Nice Piano"), file.presets()[0].name());
  // file.presets()[0].dump("", 0);
//
//  auto samples = file.sampleSourceCollection()[0];
//  XCTAssertEqual(samples.size(), size_t(115504));
//
//  XCTAssertEqualWithAccuracy(samples[0], -0.00103759765625, 0.000001);
}

//- (void)testSamples {
//  auto& file = self.contexts->context2.file();
//  auto samples = file.sampleSourceCollection()[0];
//
//  off_t sampleOffset = 246;
//  XCTAssertEqual(samples.size(), size_t(115504));
//  XCTAssertEqualWithAccuracy(samples[0], -0.00103759765625, self.epsilon);
//
//  int fd = self.contexts->context2.fd();
//  off_t pos = ::lseek(fd, sampleOffset, SEEK_SET);
//  XCTAssertEqual(pos, sampleOffset);
//
//  int16_t rawSamples[4];
//  ::read(fd, &rawSamples, sizeof(rawSamples));
//
//  XCTAssertEqualWithAccuracy(rawSamples[0] * NormalizedSampleSource::normalizationScale, samples[0], self.epsilon);
//  XCTAssertEqualWithAccuracy(rawSamples[1] * NormalizedSampleSource::normalizationScale, samples[1], self.epsilon);
//  XCTAssertEqualWithAccuracy(rawSamples[2] * NormalizedSampleSource::normalizationScale, samples[2], self.epsilon);
//  XCTAssertEqualWithAccuracy(rawSamples[3] * NormalizedSampleSource::normalizationScale, samples[3], self.epsilon);
//
//  // file.dumpThreaded();
//}

- (void)testDump0 {
  const auto& file = self.contexts->context0.file();
  XCTAssertNoThrow(file.dump());
  XCTAssertNoThrow(file.dumpThreaded());
}

- (void)testDump1 {
  const auto& file = self.contexts->context1.file();
  XCTAssertNoThrow(file.dumpThreaded());
}

- (void)testDump2 {
  const auto& file = self.contexts->context2.file();
  XCTAssertNoThrow(file.dumpThreaded());
}

- (void)testLoadPath {
  XCTAssertEqual(SF2::IO::File("/dev/null").load(), SF2::IO::File::LoadResponse::invalidFormat);
  XCTAssertEqual(SF2::IO::File("/dev/zero").load(), SF2::IO::File::LoadResponse::invalidFormat);
  XCTAssertEqual(SF2::IO::File("/dev/urandom").load(), SF2::IO::File::LoadResponse::invalidFormat);
  NSURL* b1 = [TestResources getBadResourceUrl:0];
  XCTAssertNotEqual(SF2::IO::File([[b1 absoluteString] UTF8String]).load(), SF2::IO::File::LoadResponse::ok);
  NSURL* b2 = [TestResources getResourceUrl:0];
  XCTAssertEqual(SF2::IO::File([[b2 absoluteString] UTF8String]).load(), SF2::IO::File::LoadResponse::ok);
}

- (void)testLoadFileDescriptor {
  XCTAssertEqual(SF2::IO::File().load(-1), SF2::IO::File::LoadResponse::invalidFormat);
  XCTAssertEqual(SF2::IO::File().load(0), SF2::IO::File::LoadResponse::invalidFormat);
  XCTAssertEqual(SF2::IO::File().load(1), SF2::IO::File::LoadResponse::invalidFormat);
  NSURL* b1 = [TestResources getBadResourceUrl:0];
  XCTAssertNotEqual(SF2::IO::File().load([NSFileHandle fileHandleForReadingFromURL:b1 error:nil].fileDescriptor),
                    SF2::IO::File::LoadResponse::ok);
  NSURL* b2 = [TestResources getResourceUrl:0];
  XCTAssertEqual(SF2::IO::File().load([NSFileHandle fileHandleForReadingFromURL:b2 error:nil].fileDescriptor),
                 SF2::IO::File::LoadResponse::ok);
}
@end
