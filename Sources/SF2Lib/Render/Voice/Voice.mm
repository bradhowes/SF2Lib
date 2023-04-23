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
gainEnvelope_{sampleRate},
modulatorEnvelope_{sampleRate},
modulatorLFO_{},
vibratoLFO_{},
filter_{sampleRate},
voiceIndex_{voiceIndex},
active_{false},
keyDown_{false}
{}

void
Voice::start(const State::Config& config, const NRPN& nrpn) noexcept
{
  config.sampleSource().load();

  const auto& sampleHeader{config.sampleSource().header()};

  // All components of the Voice must properly reset their state prior to rendering a note. Many attributes are created

  state_.prepareForVoice(config, nrpn);
  
  loopingMode_ = loopingMode();
  
  pitch_.configure(sampleHeader);
  gainEnvelope_.configureVolumeEnvelope(state_);
  modulatorEnvelope_.configureModulationEnvelope(state_);
  sampleGenerator_.configure(config.sampleSource());

  modulatorLFO_ = LFO::forModulator(state_);
  vibratoLFO_ = LFO::forVibrato(state_);

  assert(config.sampleSource().isLoaded());
  noiseFloorOverMagnitude_ = config.sampleSource().noiseFloorOverMagnitude();
  noiseFloorOverMagnitudeOfLoop_ = config.sampleSource().noiseFloorOverMagnitudeOfLoop();

  filter_.reset();
  active_ = true;
  keyDown_ = true;
}
