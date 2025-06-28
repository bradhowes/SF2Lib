#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "TestResources.hpp"
#import "Engine.hpp"

@interface EngineTests : XCTestCase

@end

@implementation EngineTests {
  SF2Engine* engine;
}

- (void)setUp {
  engine = new SF2Engine(48000.0, 48);
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

- (void)testCreateLoadFileUseIndex {
  auto url = [TestResources getResourceUrl:0];
  auto data = engine->createLoadFileUsePreset(url.path.UTF8String, 123);
  XCTAssertTrue(data.size() > url.path.length);
}

- (void)testCreateUseIndex {
  auto data = engine->createUsePreset(59);
  XCTAssertEqual(6, data.size());
}

- (void)testCreateResetCommand {
  auto data = engine->createResetCommand();
  XCTAssertEqual(3, data.size());
}

- (void)testCreateUseBankProgram {
  auto data = engine->createUseBankProgram(1, 43);
  XCTAssertEqual(9, data.size());
}

- (void)testCreateChannelMessage {
  auto data = engine->createChannelMessage(0xFE, 0x01);
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
