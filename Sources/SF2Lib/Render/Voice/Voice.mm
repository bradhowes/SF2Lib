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
             Sample::Generator::Interpolator interpolator) noexcept :
state_{sampleRate, channelState},
loopingMode_{LoopingMode::none},
pitch_{state_},
sampleGenerator_{interpolator},
gainEnvelope_{sampleRate, Envelope::Generator::Kind::volume, voiceIndex},
modulatorEnvelope_{sampleRate, Envelope::Generator::Kind::modulation, voiceIndex},
modulatorLFO_{sampleRate},
vibratoLFO_{sampleRate},
filter_{sampleRate},
voiceIndex_{voiceIndex},
active_{false},
keyDown_{false}
{}

void
Voice::start(const State::Config& config) noexcept
{
  os_log_debug(log_, "starting voice: %zu", voiceIndex_);

  os_signpost_interval_begin(log_, startSignpost_, "start");

  config.sampleSource().load();
  state_.prepareForVoice(config);
  loopingMode_ = loopingMode();

  const auto& sampleSource{config.sampleSource()};

  sampleGenerator_.configure(sampleSource, state_);
  pitch_.configure(sampleSource.header());

  gainEnvelope_.configure(state_);
  modulatorEnvelope_.configure(state_);

  modulatorLFO_.configure(state_);
  vibratoLFO_.configure(state_);

  filter_.reset();

  active_ = true;
  keyDown_ = true;

  os_signpost_interval_end(log_, startSignpost_, "start");
}
