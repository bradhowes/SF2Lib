// Copyright © 2023 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Engine.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

namespace Eng = SF2::Render::Engine;

SF2Engine::SF2Engine() noexcept
: impl_{nullptr}
{
  std::cout << "SF2Engine::SF2Engine" << std::endl;
}

SF2Engine::~SF2Engine() noexcept
{
  auto allocated = impl_.get() != nullptr;
  auto useCount = impl_.use_count();
  std::cout << "SF2Engine::~SF2Engine - allocated: " << allocated << " useCount: " << useCount << std::endl;
}

void SF2Engine::create(double sampleRate, NSUInteger voiceCount)
{
  std::cout << "SF2Engine::create" << std::endl;
  impl_.reset(new Eng::Engine(sampleRate, voiceCount, Eng::Engine::Interpolator::cubic4thOrder));
}

bool
SF2Engine::setRenderingFormat(NSInteger busCount, AVAudioFormat *format, AUAudioFrameCount maxFramesToRender) const noexcept
{
  impl_->setRenderingFormat(busCount, format, maxFramesToRender);
  return impl_->isRendering();
}

AUInternalRenderBlock
SF2Engine::getRenderBlock() const noexcept {
  // Technically, this makes the class "unsafe" since it is allowing the internal engine pointer to escape its wrapper.
  // We do this under the assumption that Apple won't hold onto this block after rendering has stopped.
  NSInteger bus = 0;
  auto engine = impl_.get();
  assert(engine != nullptr);
  return ^AUAudioUnitStatus(AudioUnitRenderActionFlags* _Nonnull actionFlags, const AudioTimeStamp* _Nonnull timestamp,
                            AUAudioFrameCount frameCount, NSInteger outputBusNumber, AudioBufferList* _Nonnull output,
                            const AURenderEvent* __nullable realtimeEventListHead,
                            AURenderPullInputBlock __nullable __unsafe_unretained pullInputBlock) {
    return engine->processAndRender(timestamp, frameCount, outputBusNumber, output, realtimeEventListHead, pullInputBlock);
  };
}

AUAudioUnitStatus
SF2Engine::processAndRender(const AudioTimeStamp* timestamp, UInt32 frameCount, NSInteger outputBusNumber,
                            AudioBufferList* output, const AURenderEvent* realtimeEventListHead,
                            AURenderPullInputBlock pullInputBlock) const noexcept
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
SF2Engine::createLoadFileUsePresetPayload(std::string filePath, size_t presetIndex) noexcept
//                                          SF2::MIDI::GeneratorOverrideVector overrides) noexcept
{
  SF2::MIDI::GeneratorOverrideVector overrides;
  return SF2::Render::Engine::Engine::createLoadFileUsePresetPayload(filePath, presetIndex, overrides);
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
