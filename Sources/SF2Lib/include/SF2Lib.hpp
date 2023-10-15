// Copyright © 2023 Brad Howes. All rights reserved.

#pragma once

#include <memory>
#include <Foundation/Foundation.h>
#include <CoreAudioKit/CoreAudioKit.h>
#include <string>
#include <swift/bridging>

namespace SF2 {

namespace Render::Engine { class Engine; }

struct Engine
{
  Engine(double sampleRate, NSUInteger voiceCount);

  ~Engine();

  void setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender);

  AUAudioUnitStatus processAndRender(const AudioTimeStamp* timestamp, UInt32 frameCount, NSInteger outputBusNumber,
                                     AudioBufferList* output, const AURenderEvent* realtimeEventListHead,
                                     AURenderPullInputBlock pullInputBlock);

  SWIFT_RETURNS_INDEPENDENT_VALUE
  std::string activePresetName() const noexcept;

  NSData* createLoadSysExec(const std::string& path, size_t preset) const noexcept;

  std::vector<uint8_t> createUseIndex(size_t index) const noexcept;

  std::vector<uint8_t> createResetCommand() const noexcept;

  std::vector<std::vector<uint8_t>> createUseBankProgram(uint16_t bank, uint8_t program) const noexcept;

  std::vector<uint8_t> createChannelMessage(uint8_t channelMessage, uint8_t value) const noexcept;

private:
  std::shared_ptr<Render::Engine::Engine> impl_;
};

} // SF2::DSP namespaces
