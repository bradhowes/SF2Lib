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

  size_t activeVoiceCount() const noexcept;

  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSData* createLoadSysEx(const std::string& path, size_t index) const noexcept;

  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSData* createUseIndex(size_t index) const noexcept;

  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSData* createResetCommand() const noexcept;

  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSArray<NSData*>* createUseBankProgram(uint16_t bank, uint8_t program) const noexcept;

  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSData* createChannelMessage(uint8_t channelMessage, uint8_t value) const noexcept;

  bool monophonicModeEnabled() const noexcept;

  bool polyphonicModeEnabled() const noexcept;

  bool portamentoModeEnabled() const noexcept;

  bool oneVoicePerKeyModeEnabled() const noexcept;

  bool retriggerModeEnabled() const noexcept;

private:
  std::shared_ptr<Render::Engine::Engine> impl_;
};

} // SF2::DSP namespaces
