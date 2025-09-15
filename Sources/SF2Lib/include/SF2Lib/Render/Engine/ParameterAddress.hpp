#pragma once

#include <AudioUnit/AudioUnit.h>

namespace SF2::Render::Engine {

  /**
   Enumeration of engine-specific parameters. Some are read-only to communicate engine state to others.
   */
  enum struct ParameterAddress : AUParameterAddress
  {
    // Pretty sure this is large enough to never overlap with SF generator indices now and in the future
    // (SoundFont spec v2.01 defines 59)
    firstParameterAddress = 1000,
    portamentoModeEnabled = firstParameterAddress,
    portamentoRate,
    oneVoicePerKeyModeEnabled, // aka mono
    polyphonicModeEnabled,
    activeVoiceCount,
    retriggerModeEnabled,
    isRendering,
    activeProgramIndex,
    activeBankIndex,
    activePresetIndex,
    lastParameterAddressPlusOne
  };

}
