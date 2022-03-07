// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include "SF2Lib/Logger.hpp"

#include "SF2Lib/Entity/Generator/Index.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"

struct NRPNTestPoint;

namespace SF2::Render::Voice::State { class State; }

namespace SF2::MIDI {

/**
 Processes MIDI continuous controller (CC) messages, looking for non-registered parameter number (NRPN) messages that
 applies to SoundFont generators. When found, these messages update internal state which can then be used to revised the
 internal state of a voice, overriding the generator values defined in a SoundFont preset and/or instrument.
 */
class NRPN
{
public:
  using NRPNValues = std::array<int, size_t(Entity::Generator::Index::numValues)>;

  /**
   Constructor.

   @param channelState the record of current CC state for a MIDI channel.
   */
  NRPN(const ChannelState& channelState) : channelState_{channelState} {}

  void apply(Render::Voice::State::State& state) const;

  /**
   Process a continuous controller message.

   @param cc continuous controller index
   @param value the value assigned to the controller
   */
  void process(int cc, int value);

  /// @returns true if actively processing SoundFont generator changes.
  bool isActive() const { return active_; }

  /// @returns collection of generator values possibly set by NRPN messages.
  const NRPNValues& values() const { return nrpnValues_; }

private:
  const ChannelState& channelState_;
  NRPNValues nrpnValues_{0};

  size_t index_{0};
  bool active_{false};

  friend NRPNTestPoint;

  inline static Logger log_{Logger::Make("MIDI", "NRPN")};
};

}
