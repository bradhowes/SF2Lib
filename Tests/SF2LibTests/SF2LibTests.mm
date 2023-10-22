#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "TestResources.hpp"
#import "SF2Lib.hpp"

@interface SF2LibTests : XCTestCase

@end

@implementation SF2LibTests {
  SF2::Engine* engine;
}

- (void)setUp {
  engine = new SF2::Engine(48000.0, 48);
}

- (void)tearDown {
  delete engine;
  engine = nullptr;
}

- (void)testSetRenderingFormat {
  auto audioFormat = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000.0 channels:2];
  engine->setRenderingFormat(3, audioFormat, 512);
  // There is no way to check this right now
}

- (void)testActivePresetName {
  auto value = engine->activePresetName();
  XCTAssertEqual("", value);
}

- (void)testCreateLoadFileUseIndex {
  auto url = [TestResources getResourceUrl:0];
  auto data = engine->createLoadFileUseIndex(url.path.UTF8String, 123);
  XCTAssertNotNil(data);
  XCTAssertTrue(data.length > url.path.length);
}

- (void)testCreateUseIndex {
  auto data = engine->createUseIndex(59);
  XCTAssertNotNil(data);
  XCTAssertEqual(6, data.length);
}

- (void)testCreateResetCommand {
  auto data = engine->createResetCommand();
  XCTAssertNotNil(data);
  XCTAssertEqual(1, data.length);
}

- (void)testCreateUseBankProgram {
  auto data = engine->createUseBankProgram(1, 43);
  XCTAssertNotNil(data);
  XCTAssertEqual(3, data.count);
}

- (void)testCreateChannelMessage {
  auto data = engine->createChannelMessage(0xFE, 0x01);
  XCTAssertNotNil(data);
  XCTAssertEqual(3, data.length);
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
