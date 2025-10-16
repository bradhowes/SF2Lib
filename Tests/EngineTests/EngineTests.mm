#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "TestResources.hpp"
#import "SF2Engine.hpp"

@interface EngineTests : XCTestCase

@end

@implementation EngineTests {
  SF2Engine* engine;
}

- (void)setUp {
  engine = new SF2Engine();
  engine->create(48000.0, 48);
}

- (void)tearDown {
  delete engine;
  engine = nullptr;
}

- (void)testSetRenderingFormat {
  auto audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000.0 channels:2];
  XCTAssertTrue(engine->setRenderingFormat(3, audioFormat, 512));
}

- (void)testActivePresetName {
  auto value = engine->activePresetName();
  XCTAssertEqual("", value);
}

- (void)testCreateLoadFileUseIndexNoOverrides {
  auto url = [TestResources getResourceUrl:0];
  // auto overrides = std::vector<SF2::MIDI::GeneratorOverride>();
  auto data = engine->createLoadFileUsePresetPayload(url.path.UTF8String, 123);
  XCTAssertTrue(data.size() > url.path.length);
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
  auto data = engine->createResetCommandPayload();
  XCTAssertEqual(1, data.size());
}

- (void)testCreateUseBankProgram {
  auto data = engine->createUseBankProgramPayload(1, 43);
  XCTAssertEqual(9, data.size());
}

- (void)testCreateChannelMessage {
  auto data = engine->createChannelMessagePayload(0xFE, 0x01);
  XCTAssertEqual(3, data.size());
}

- (void)testActiveVoiceCount {
  XCTAssertEqual(0, engine->activeVoiceCount());
}

- (void)testMonophonicModeEnabled {
  XCTAssertEqual(false, engine->monophonicModeEnabled());
}

- (void)testPolyphonicModeEnabled {
  XCTAssertEqual(true, engine->polyphonicModeEnabled());
}

- (void)testPortamentoModeEnabled {
  XCTAssertEqual(false, engine->portamentoModeEnabled());
}

- (void)testkOneVoicePerKeyModeEnabled {
  XCTAssertEqual(false, engine->oneVoicePerKeyModeEnabled());
}

- (void)testRetriggerModeEnabled {
  XCTAssertEqual(true, engine->retriggerModeEnabled());
}

@end
