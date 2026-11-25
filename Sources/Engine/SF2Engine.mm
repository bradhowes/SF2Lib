// Copyright © 2023 Brad Howes. All rights reserved.

#include <algorithm>
#include <iostream>

#include "SF2Engine.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"
#include "SF2Lib/MIDI/MIDI.hpp"

namespace Eng = SF2::Render::Engine;

SF2Engine::SF2Engine(double sampleRate, NSUInteger voiceCount)
: impl_{std::make_shared<Eng::Engine>(sampleRate, std::clamp<size_t>(voiceCount, 1, Eng::traits::maxVoiceCount),
                                      Eng::Engine::Interpolator::cubic4thOrder, 0.85)}
{}

size_t
SF2Engine::maxVoiceCount() noexcept
{
  return Eng::traits::maxVoiceCount;
}

size_t
SF2Engine::voiceCountLimit() const noexcept
{
  return impl_->voiceCountLimit();
}

bool
SF2Engine::setRenderingFormat(NSInteger busCount, AVAudioFormat *format, AUAudioFrameCount maxFramesToRender) const noexcept
{
  impl_->setRenderingFormat(busCount, format, maxFramesToRender);
  return impl_->isRendering();
}

AUInternalRenderBlock
SF2Engine::getRenderBlock() const noexcept {
  // The block captures its own copy of the shared pointer (blocks copy-construct captured C++ objects), so the engine
  // lives as long as the block does. It used to capture the raw pointer, which dangled once the last SF2Engine went
  // away while CoreAudio still held the block.
  auto engine = impl_;
  return ^AUAudioUnitStatus(AudioUnitRenderActionFlags* _Nonnull actionFlags, const AudioTimeStamp* _Nonnull timestamp,
                            AUAudioFrameCount frameCount, NSInteger outputBusNumber, AudioBufferList* _Nonnull output,
                            const AURenderEvent* __nullable realtimeEventListHead,
                            AURenderPullInputBlock __nullable __unsafe_unretained) {
    // NOTE: do not pass on the AURenderPullInputBlock since we are the source of all audio. Doing so will result in an AU error
    // from the render routine resulting in no audio output.
    return engine->processAndRender(timestamp, frameCount, outputBusNumber, output, realtimeEventListHead, nullptr);
  };
}

AUAudioUnitStatus
SF2Engine::processAndRender(const AudioTimeStamp* timestamp, UInt32 frameCount, NSInteger outputBusNumber,
                            AudioBufferList* output, const AURenderEvent* realtimeEventListHead,
                            AURenderPullInputBlock) const noexcept
{
  return impl_->processAndRender(timestamp, frameCount, outputBusNumber, output, realtimeEventListHead, nullptr);
}

AUParameterTree*
SF2Engine::getParameterTree() const noexcept
{
  return impl_->parameterTree();
}

std::string
SF2Engine::activePresetName() const
{
  return impl_->activePresetName();
}

std::vector<uint8_t>
SF2Engine::createLoadFileUsePresetPayload(std::string filePath, size_t presetIndex)
//                                          SF2::MIDI::GeneratorOverrideVector overrides) noexcept
{
  SF2::MIDI::GeneratorOverrideVector overrides;
  return SF2::Render::Engine::Engine::createLoadFileUsePresetPayload(filePath, presetIndex, overrides);
}

SF2::IO::File::LoadResponse
SF2Engine::loadFileAndPreset(std::string path, size_t presetIndex) {
  return impl_->loadFileAndPreset(path, presetIndex);
}

SF2::IO::File::LoadResponse
SF2Engine::loadFileAndPreset(int fd, size_t presetIndex) {
  return impl_->loadFileAndPreset(fd, presetIndex);
}

std::vector<uint8_t>
SF2Engine::createLoadBookmarkUsePresetPayload(NSData* bookmark, size_t presetIndex)
//                                          SF2::MIDI::GeneratorOverrideVector overrides) noexcept
{
  SF2::MIDI::GeneratorOverrideVector overrides;
  return SF2::Render::Engine::Engine::createLoadBookmarkUsePresetPayload(bookmark, presetIndex, overrides);
}

SF2::IO::File::LoadResponse
SF2Engine::loadBookmarkAndPreset(NSData* bookmark, size_t presetIndex) {
  return impl_->loadBookmarkAndPreset(bookmark, presetIndex);
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
