#include <iostream>

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

- (void)testDestruction {
  delete self.engine;
  self.engine = nullptr;
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

- (void)testCreateLoadBookmarkPresetPayload {
  uint8_t bytes[] = {1, 2, 3, 4, 5, 6};
  auto data = [NSData dataWithBytes: bytes length: 6];
  auto payload = self.engine->createLoadBookmarkUsePresetPayload(data, 123);
  //  for (auto index = 0; index < payload.size(); ++index) {
  //    std::cout << "XCTAssertEqual(payload[" << index << "], " << int(payload[index]) << ");\n";
  //  }
  XCTAssertEqual(payload[0], 240);
  XCTAssertEqual(payload[1], 126);
  XCTAssertEqual(payload[2], 1);
  XCTAssertEqual(payload[3], 0);
  XCTAssertEqual(payload[4], 0);
  XCTAssertEqual(payload[5], 0);
  XCTAssertEqual(payload[6], 0);
  XCTAssertEqual(payload[7], 0);
  XCTAssertEqual(payload[8], 123);
  XCTAssertEqual(payload[9], 0);
  XCTAssertEqual(payload[10], 0);
  XCTAssertEqual(payload[11], 0);
  XCTAssertEqual(payload[12], 0);
  XCTAssertEqual(payload[13], 0);
  XCTAssertEqual(payload[14], 0);
  XCTAssertEqual(payload[15], 0);
  XCTAssertEqual(payload[16], 0);
  XCTAssertEqual(payload[17], 0);
  XCTAssertEqual(payload[18], 0);
  XCTAssertEqual(payload[19], 0);
  XCTAssertEqual(payload[20], 0);
  XCTAssertEqual(payload[21], 0);
  XCTAssertEqual(payload[22], 0);
  XCTAssertEqual(payload[23], 0);
  XCTAssertEqual(payload[24], 65);
  XCTAssertEqual(payload[25], 81);
  XCTAssertEqual(payload[26], 73);
  XCTAssertEqual(payload[27], 68);
  XCTAssertEqual(payload[28], 66);
  XCTAssertEqual(payload[29], 65);
  XCTAssertEqual(payload[30], 85);
  XCTAssertEqual(payload[31], 71);
  XCTAssertEqual(payload[32], 247);
}

- (void)testLoadFileNameAndPreset {
  auto path = [TestResources getResourcePath:0];
  auto result = self.engine->loadFileAndPreset(path, 0);
  XCTAssertEqual(result, SF2::IO::File::LoadResponse::ok);
  XCTAssertTrue("Piano 1" == self.engine->activePresetName());
  result = self.engine->loadFileAndPreset("", 1);
  XCTAssertEqual(result, SF2::IO::File::LoadResponse::ok);
  XCTAssertTrue("Piano 2" == self.engine->activePresetName());
}

- (void)testLoadFileDescriptorAndPreset {
  auto path = [TestResources getResourcePath:0];
  auto fd = ::open(path.c_str(), O_RDONLY);
  auto result = self.engine->loadFileAndPreset(fd, 0);
  XCTAssertEqual(result, SF2::IO::File::LoadResponse::ok);
  XCTAssertTrue("Piano 1" == self.engine->activePresetName());
}

- (void)testLoadFileAndPresetNotFound {
  auto result = self.engine->loadFileAndPreset(std::string("this does not exist"), 0);
  XCTAssertEqual(result, SF2::IO::File::LoadResponse::notFound);
}

- (void)testLoadBookmarkUsePresetNotFound {
  uint8_t bytes[] = {1, 2, 3, 4, 5, 6};
  auto data = [NSData dataWithBytes: bytes length: 6];
  auto result = self.engine->loadBookmarkAndPreset(data, 123);
  XCTAssertEqual(result, SF2::IO::File::LoadResponse::notFound);
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

- (void)testGetRenderBlock {
  auto audioFormat = [[AVAudioFormat alloc]
                      initStandardFormatWithSampleRate:48000.0
                      channelLayout:[[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono]];
  self.engine->setRenderingFormat(3, audioFormat, 512);

  auto block = self.engine->getRenderBlock();
  XCTAssertTrue(block != nullptr);
  auto timestamp = AudioTimeStamp();
  AudioUnitRenderActionFlags actionFlags = kAudioUnitRenderAction_PreRender;
  auto audioBufferList = AudioBufferList();
  auto result = block(&actionFlags, &timestamp, 4096, 0, &audioBufferList, nullptr, nullptr);
  XCTAssertEqual(result, kAudioUnitErr_TooManyFramesToProcess);
}

- (void)testProcessAndRender {
  auto audioFormat = [[AVAudioFormat alloc]
                      initStandardFormatWithSampleRate:48000.0
                      channelLayout:[[AVAudioChannelLayout alloc] initWithLayoutTag:kAudioChannelLayoutTag_Mono]];
  self.engine->setRenderingFormat(3, audioFormat, 512);

  auto timestamp = AudioTimeStamp();
  auto audioBufferList = AudioBufferList();
  auto result = self.engine->processAndRender(&timestamp, 4096, 0, &audioBufferList, nullptr, nullptr);
  XCTAssertEqual(result, kAudioUnitErr_TooManyFramesToProcess);
}

- (void)testGetParameterTree {
  XCTAssertNotNil(self.engine->getParameterTree());
}

- (void)testCreateAllNotesOffPayload {
  auto payload = engine->createAllNotesOffPayload();
  auto expected = std::array<uint8_t, 3>{0xB0, 0x7B, 0};
  XCTAssertTrue(payload == expected);
}

- (void)testCreateAllSoundOffPayload {
  auto payload = engine->createAllSoundOffPayload();
  auto expected = std::array<uint8_t, 3>{0xB0, 0x78, 0};
  XCTAssertTrue(payload == expected);
}

@end
