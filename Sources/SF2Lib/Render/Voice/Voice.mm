// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <utility>

#include "SF2Lib/Render/Envelope/Generator.hpp"

#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

using namespace SF2::MIDI;
using namespace SF2::Render::Voice;
using namespace SF2::Entity::Generator;

Voice::Voice(Float sampleRate, const ChannelState& channelState, size_t voiceIndex,
             Sample::Interpolator interpolator) noexcept :
state_{sampleRate, channelState},
loopingMode_{LoopingMode::none},
pitch_{state_},
sampleGenerator_{interpolator},
volumeEnvelope_{voiceIndex},
modulatorEnvelope_{voiceIndex},
modulatorLFO_{sampleRate},
vibratoLFO_{sampleRate},
filter_{sampleRate},
active_{false},
keyDown_{false},
voiceIndex_{voiceIndex}
{}

void
Voice::configure(const State::Config& config) noexcept
{
  os_signpost_interval_begin(log_, configSignpost_, "start");

  state_.prepareForVoice(config);
  sampleGenerator_.configure(config.sampleSource(), state_);
  pitch_.configure(config.sampleSource().header());

  os_signpost_interval_end(log_, configSignpost_, "end");
}

Voice::LoopingMode
Voice::loopingMode() const noexcept
{
  switch (state_.unmodulated(Index::sampleModes)) {
    case 1: return LoopingMode::activeEnvelope;
    case 3: return LoopingMode::duringKeyPress;
    default: return LoopingMode::none;
  }
}

void
Voice::start() noexcept
{
  os_signpost_interval_begin(log_, startSignpost_, "start");

  active_ = true;
  keyDown_ = true;
  filter_.reset();

  loopingMode_ = loopingMode();
  initialAttenuation_ = DSP::centibelsToAttenuation(state_.modulated(Index::initialAttenuation));

  volumeEnvelope_.configure(state_);
  modulatorEnvelope_.configure(state_);
  modulatorLFO_.configure(state_);
  vibratoLFO_.configure(state_);

  sampleGenerator_.start();

  os_signpost_interval_end(log_, startSignpost_, "start");
}

void
Voice::releaseKey(const ReleaseKeyState& releaseKeyState) noexcept
{
  if (releaseKeyState.pedalState.sustainPedalActive ||
      (releaseKeyState.pedalState.sostenutoPedalActive && sostenutoActive_)) {
    postponedRelease_ = true;
  } else {
    keyDown_ = false;
    volumeEnvelope_.gate(false);
    modulatorEnvelope_.gate(false);
  }
}
