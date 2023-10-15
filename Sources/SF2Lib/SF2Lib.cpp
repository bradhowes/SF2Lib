// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

namespace Eng = SF2::Render::Engine;

SF2::Engine::Engine(double sampleRate, NSUInteger voiceCount)
: impl_{new Eng::Engine(sampleRate, voiceCount,
                        Eng::Engine::Interpolator::cubic4thOrder)}
{
  ;
}

SF2::Engine::~Engine()
{
  impl_.reset();
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
SF2::Engine::createLoadSysExec(const std::string& path, size_t preset) const noexcept
{
  auto value = SF2::Render::Engine::Engine::createLoadSysExec(path, preset);
  auto data = [[NSMutableData alloc] initWithBytes:value.data() length:value.size()];
  return data;
}

std::vector<uint8_t>
SF2::Engine::createUseIndex(size_t index) const noexcept
{
  return SF2::Render::Engine::Engine::createUseIndex(index);
}

std::vector<uint8_t>
SF2::Engine::createResetCommand() const noexcept
{
  return SF2::Render::Engine::Engine::createResetCommand();
}

std::vector<std::vector<uint8_t>>
SF2::Engine::createUseBankProgram(uint16_t bank, uint8_t program) const noexcept
{
  return SF2::Render::Engine::Engine::createUseBankProgram(bank, program);
}

std::vector<uint8_t> 
SF2::Engine::createChannelMessage(uint8_t channelMessage, uint8_t value) const noexcept
{
  return SF2::Render::Engine::Engine::createChannelMessage(MIDI::ControlChange(channelMessage), value);
}
