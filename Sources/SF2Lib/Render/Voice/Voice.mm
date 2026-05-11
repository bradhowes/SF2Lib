// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#include <cmath>
#include <utility>

#include "SF2Lib/Render/Envelope/Generator.hpp"

#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

using namespace SF2::MIDI;
using namespace SF2::Render::Voice;
using namespace SF2::Entity::Generator;

void
Voice::initialize(size_t voiceIndex, Float sampleRate, Sample::Interpolator interpolator) noexcept
{
  voiceIndex_ = voiceIndex;
  sampleGenerator_.setInterpolator(interpolator);
  state_.setSampleRate(sampleRate);
  filter_.setSampleRate(sampleRate);
}

void
Voice::configure(const State::Config& config, const MIDI::ChannelState& channelState) noexcept
{
  os_signpost_interval_begin(log_, configSignpost_, "start");

  state_.prepareForVoice(config, channelState);
  sampleGenerator_.configure(config.sampleSource(), state_);
  pitch_.configure(config.sampleSource().header());
  filter_.reset();

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
    os_log_info(log_, "releaseKey - postponed due to pedal state");
  } else {
    keyDown_ = false;
    volumeEnvelope_.noteReleased();
    modulatorEnvelope_.noteReleased();
  }
}
