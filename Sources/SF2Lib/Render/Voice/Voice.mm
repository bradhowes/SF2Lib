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
             Sample::Generator::Interpolator interpolator) noexcept :
state_{sampleRate, channelState},
loopingMode_{LoopingMode::none},
pitch_{state_},
sampleGenerator_{state_, interpolator},
gainEnvelope_{},
modulatorEnvelope_{},
modulatorLFO_{},
vibratoLFO_{},
filter_{sampleRate},
voiceIndex_{voiceIndex}
{}

Voice::Voice(Voice&& rhs) noexcept :
state_{std::move(rhs.state_)},
loopingMode_{rhs.loopingMode_},
pitch_{std::move(rhs.pitch_)},
sampleGenerator_{std::move(rhs.sampleGenerator_)},
gainEnvelope_{std::move(rhs.gainEnvelope_)},
modulatorEnvelope_{std::move(rhs.modulatorEnvelope_)},
modulatorLFO_{std::move(rhs.modulatorLFO_)},
vibratoLFO_{std::move(rhs.vibratoLFO_)},
filter_{std::move(rhs.filter_)},
voiceIndex_{rhs.voiceIndex_},
releasedKey_{},
done_{}
{
  ;
}

void
Voice::configure(const State::Config& config, const NRPN& nrpn) noexcept
{
  config.sampleSource().load();

  const auto& sampleHeader{config.sampleSource().header()};

  // All components of the Voice must properly reset their state prior to rendering a note. Many attributes are created

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
  
  done_.clear();
  releasedKey_.clear();
}
