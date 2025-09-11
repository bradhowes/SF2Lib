// Copyright © 2023 Brad Howes. All rights reserved.

#include "SF2Engine.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

namespace Eng = SF2::Render::Engine;

SF2Engine::SF2Engine(double sampleRate, NSUInteger voiceCount)
: impl_{new Eng::Engine(sampleRate, voiceCount, Eng::Engine::Interpolator::cubic4thOrder)}
{
  ;
}

SF2Engine::~SF2Engine() noexcept
{
  ;
}

bool
SF2Engine::setRenderingFormat(NSInteger busCount, AVAudioFormat *format, AUAudioFrameCount maxFramesToRender)
{
  impl_->setRenderingFormat(busCount, format, maxFramesToRender);
  return impl_->isRendering();
}

AUAudioUnitStatus
SF2Engine::processAndRender(const AudioTimeStamp *timestamp, UInt32 frameCount, NSInteger outputBusNumber,
                              AudioBufferList *output, const AURenderEvent *realtimeEventListHead,
                              AURenderPullInputBlock pullInputBlock)
{
  return impl_->processAndRender(timestamp, frameCount, outputBusNumber, output, realtimeEventListHead, pullInputBlock);
}

AUParameterTree*
SF2Engine::getParameterTree() const noexcept
{
  return impl_->parameterTree();
}

std::string
SF2Engine::activePresetName() const noexcept
{
  return impl_->activePresetName();
}

std::vector<uint8_t>
SF2Engine::createLoadFileUsePresetPayload(const std::string& path, size_t preset, double gain, double pan) noexcept
{
  return SF2::Render::Engine::Engine::createLoadFileUsePresetPayload(path, preset, gain, pan);
}

std::vector<uint8_t>
SF2Engine::createUsePresetPayload(size_t preset, double gain, double pan) noexcept
{
  return SF2::Render::Engine::Engine::createUsePresetPayload(preset, gain, pan);
}

std::array<uint8_t, 1>
SF2Engine::createResetCommandPayload() noexcept
{
  return SF2::Render::Engine::Engine::createResetCommandPayload();
}

std::array<uint8_t, 9>
SF2Engine::createUseBankProgramPayload(uint16_t bank, uint8_t program) noexcept
{
  return SF2::Render::Engine::Engine::createUseBankProgramPayload(bank, program);
}

std::array<uint8_t, 3>
SF2Engine::createChannelMessagePayload(uint8_t channelMessage, uint8_t content) noexcept
{
  return SF2::Render::Engine::Engine::createChannelMessagePayload(SF2::MIDI::ControlChange(channelMessage), content );
}

std::array<uint8_t, 3>
SF2Engine::createAllNotesOffPayload() noexcept
{
  return SF2::Render::Engine::Engine::createAllNotesOffPayload();
}

std::array<uint8_t, 3>
SF2Engine::createAllSoundOffPayload() noexcept
{
  return SF2::Render::Engine::Engine::createAllSoundOffPayload();
}

size_t
SF2Engine::activeVoiceCount() const noexcept
{
  return impl_->activeVoiceCount();
}

bool
SF2Engine::monophonicModeEnabled() const noexcept
{
  return impl_->monophonicModeEnabled();
}

bool
SF2Engine::polyphonicModeEnabled() const noexcept
{
  return impl_->polyphonicModeEnabled();
}

bool
SF2Engine::portamentoModeEnabled() const noexcept
{
  return impl_->portamentoModeEnabled();
}

bool
SF2Engine::oneVoicePerKeyModeEnabled() const noexcept
{
  return impl_->oneVoicePerKeyModeEnabled();
}

bool
SF2Engine::retriggerModeEnabled() const noexcept
{
  return impl_->retriggerModeEnabled();
}
