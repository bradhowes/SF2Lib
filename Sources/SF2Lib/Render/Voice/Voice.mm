// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>

#include "SF2Lib/Render/Envelope/Generator.hpp"

#include "SF2Lib/Render/Voice/Sample/Bounds.hpp"
#include "SF2Lib/Render/Voice/State/Config.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

using namespace SF2::MIDI;
using namespace SF2::Render::Voice;
using namespace SF2::Entity::Generator;

Voice::Voice(Float sampleRate, const ChannelState& channelState, size_t voiceIndex,
             Sample::Generator::Interpolator interpolator) :
state_{sampleRate, channelState},
loopingMode_{none},
pitch_{state_},
sampleGenerator_{state_, interpolator},
gainEnvelope_{},
modulatorEnvelope_{},
modulatorLFO_{},
vibratoLFO_{},
filter_{sampleRate},
voiceIndex_{voiceIndex},
samples_{}
{
  samples_.reserve(512);
  samples_.resize(512, 0.0f);
}

void
Voice::configure(const State::Config& config, const NRPN& nrpn)
{
  config.sampleSource().load();

  const auto& sampleHeader{config.sampleSource().header()};
  os_log_debug(log_, "configure - %d %d %d", sampleHeader.isLeft(), sampleHeader.isRight(),
               sampleHeader.sampleLinkIndex());
  
  state_.prepareForVoice(config, nrpn);
  
  loopingMode_ = loopingMode();
  pitch_.configure(sampleHeader);
  gainEnvelope_ = Envelope::Generator::forVol(state_);
  modulatorEnvelope_ = Envelope::Generator::forMod(state_);
  sampleGenerator_.configure(config.sampleSource());
  modulatorLFO_ = LFO::forModulator(state_);
  vibratoLFO_ = LFO::forVibrato(state_);

  assert(config.sampleSource().isLoaded());
  noiseFloorOverMagnitude_ = config.sampleSource().noiseFloorOverMagnitude();
  noiseFloorOverMagnitudeOfLoop_ = config.sampleSource().noiseFloorOverMagnitudeOfLoop();

  filter_.reset();
  
  done_ = false;
}
