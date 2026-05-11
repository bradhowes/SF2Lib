#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "TestResources.hpp"
#import "SF2Engine.hpp"

@interface EngineTests : XCTestCase
@property (nonatomic) SF2Engine* engine;
@end

@implementation EngineTests

@synthesize engine;

- (void)setUp {
  self.engine = new SF2Engine();
  self.engine->create(48000.0, 48);
}

- (void)tearDown {
}

- (void)testSetRenderingFormat {
  auto audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000.0 channels:2];
  XCTAssertTrue(self.engine->setRenderingFormat(3, audioFormat, 512));
}

- (void)testActivePresetName {
  auto value = self.engine->activePresetName();
  XCTAssertEqual("", value);
}

- (void)testCreateLoadFileUseIndexNoOverrides {
  auto path = [TestResources getResourcePath:0];
  // auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
  auto data = self.engine->createLoadFileUsePresetPayload(path, 123);
  XCTAssertTrue(data.size() > path.size());
}

//- (void)testCreateLoadFileUseIndexWithOverrides {
//  auto url = [TestResources getResourceUrl:0];
//  auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
//  overrides.emplace_back(123, 456);
//  overrides.emplace_back(124, -23);
//  auto data = engine->createLoadFileUsePresetPayload(url.path.UTF8String, 123, overrides);
//  XCTAssertTrue(data.size() > url.path.length);
//}

- (void)testCreateResetCommand {
  auto data = self.engine->createResetCommandPayload();
  XCTAssertEqual(size_t(1), data.size());
}

- (void)testCreateUseBankProgram {
  auto data = self.engine->createUseBankProgramPayload(1, 43);
  XCTAssertEqual(size_t(9), data.size());
}

- (void)testCreateChannelMessage {
  auto data = self.engine->createChannelMessagePayload(0xFE, 0x01);
  XCTAssertEqual(size_t(3), data.size());
}

- (void)testActiveVoiceCount {
  XCTAssertEqual(size_t(0), self.engine->activeVoiceCount());
}

- (void)testMonophonicModeEnabled {
  XCTAssertEqual(false, self.engine->monophonicModeEnabled());
}

- (void)testPolyphonicModeEnabled {
  XCTAssertEqual(true, self.engine->polyphonicModeEnabled());
}

- (void)testPortamentoModeEnabled {
  XCTAssertEqual(false, self.engine->portamentoModeEnabled());
}

- (void)testkOneVoicePerKeyModeEnabled {
  XCTAssertEqual(false, self.engine->oneVoicePerKeyModeEnabled());
}

- (void)testRetriggerModeEnabled {
  XCTAssertEqual(true, self.engine->retriggerModeEnabled());
}

@end
