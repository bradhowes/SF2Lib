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
sampleGenerator_{state_, interpolator},
gainEnvelope_{sampleRate, Envelope::Generator::Kind::volume},
modulatorEnvelope_{sampleRate, Envelope::Generator::Kind::modulation},
modulatorLFO_{sampleRate, LFO::Kind::modulator},
vibratoLFO_{sampleRate, LFO::Kind::vibrato},
filter_{sampleRate},
voiceIndex_{voiceIndex},
active_{false},
keyDown_{false}
{}

void
Voice::start(const State::Config& config, const NRPN& nrpn) noexcept
{
  os_signpost_interval_begin(log_, startSignpost_, "start");

  config.sampleSource().load();
  assert(config.sampleSource().isLoaded());

  // All components of the Voice must properly reset their state prior to rendering a note. Many attributes are created
  state_.prepareForVoice(config, nrpn);
  loopingMode_ = loopingMode();

  const auto& sampleHeader{config.sampleSource().header()};

  pitch_.configure(sampleHeader);
  sampleGenerator_.configure(config.sampleSource());
  gainEnvelope_.configure(state_);
  modulatorEnvelope_.configure(state_);
  modulatorLFO_.configure(state_);
  vibratoLFO_.configure(state_);
  filter_.reset();

  noiseFloorOverMagnitude_ = config.sampleSource().noiseFloorOverMagnitude();
  noiseFloorOverMagnitudeOfLoop_ = config.sampleSource().noiseFloorOverMagnitudeOfLoop();

  active_ = true;
  keyDown_ = true;

  os_signpost_interval_end(log_, startSignpost_, "start");
}
