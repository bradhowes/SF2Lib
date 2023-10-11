// Copyright © 2023 Brad Howes. All rights reserved.

#pragma once

#include <memory>
#include <Foundation/Foundation.h>
#include <CoreAudioKit/CoreAudioKit.h>

#include <string>

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

  std::string activePresetName() const;

private:
  std::shared_ptr<Render::Engine::Engine> impl_;
};

} // SF2::DSP namespaces
