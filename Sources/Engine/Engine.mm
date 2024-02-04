// Copyright © 2023 Brad Howes. All rights reserved.

#include "Engine.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

namespace Eng = SF2::Render::Engine;

SF2::Engine::Engine(double sampleRate, NSUInteger voiceCount)
: impl_{new Eng::Engine(sampleRate, voiceCount, Eng::Engine::Interpolator::cubic4thOrder)}
{
  ;
}

void
SF2::Engine::setRenderingFormat(NSInteger busCount, AVAudioFormat *format, AUAudioFrameCount maxFramesToRender)
{
  impl_->setRenderingFormat(busCount, format, maxFramesToRender);
}

AUAudioUnitStatus
SF2::Engine::processAndRender(const AudioTimeStamp *timestamp, UInt32 frameCount, NSInteger outputBusNumber,
                              AudioBufferList *output, const AURenderEvent *realtimeEventListHead,
                              AURenderPullInputBlock pullInputBlock)
{
  return impl_->processAndRender(timestamp, frameCount, outputBusNumber, output, realtimeEventListHead, pullInputBlock);
}

std::string
SF2::Engine::activePresetName() const noexcept
{
  return impl_->activePresetName();
}

NSData*
SF2::Engine::createLoadFileUseIndex(const std::string& path, size_t preset) const noexcept
{
  auto value = SF2::Render::Engine::Engine::createLoadFileUseIndex(path, preset);
  auto data = [[NSMutableData alloc] initWithBytes:value.data() length:value.size()];
  return data;
}

NSData*
SF2::Engine::createUseIndex(size_t index) const noexcept
{
  auto value = SF2::Render::Engine::Engine::createUseIndex(index);
  auto data = [[NSMutableData alloc] initWithBytes:value.data() length:value.size()];
  return data;
}

NSData*
SF2::Engine::createResetCommand() const noexcept
{
  auto value = SF2::Render::Engine::Engine::createResetCommand();
  auto data = [[NSMutableData alloc] initWithBytes:value.data() length:value.size()];
  return data;
}

NSArray<NSData*>*
SF2::Engine::createUseBankProgram(uint16_t bank, uint8_t program) const noexcept
{
  auto value = SF2::Render::Engine::Engine::createUseBankProgram(bank, program);
  auto data = [[NSMutableArray alloc] initWithCapacity:value.size()];
  for (const auto& msg : value) {
    [data addObject:[[NSMutableData alloc] initWithBytes:msg.data() length:msg.size()]];
  }
  return data;
}

NSData*
SF2::Engine::createChannelMessage(uint8_t channelMessage, uint8_t content) const noexcept
{
  auto value = SF2::Render::Engine::Engine::createChannelMessage(MIDI::ControlChange(channelMessage), content );
  auto data = [[NSMutableData alloc] initWithBytes:value.data() length:value.size()];
  return data;
}

size_t
SF2::Engine::activeVoiceCount() const noexcept
{
  return impl_->activeVoiceCount();
}

bool
SF2::Engine::monophonicModeEnabled() const noexcept
{
  return impl_->monophonicModeEnabled();
}

bool
SF2::Engine::polyphonicModeEnabled() const noexcept
{
  return impl_->polyphonicModeEnabled();
}

bool
SF2::Engine::portamentoModeEnabled() const noexcept
{
  return impl_->portamentoModeEnabled();
}

bool
SF2::Engine::oneVoicePerKeyModeEnabled() const noexcept
{
  return impl_->oneVoicePerKeyModeEnabled();
}

bool
SF2::Engine::retriggerModeEnabled() const noexcept
{
  return impl_->retriggerModeEnabled();
}
