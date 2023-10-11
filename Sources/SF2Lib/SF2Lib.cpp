// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib.hpp"
#include "SF2Lib/Render/Engine/Engine.hpp"

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
SF2::Engine::activePresetName() const
{
  return impl_->activePresetName();
}
