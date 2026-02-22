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
  //
  firstParameterAddress = 1000,
  portamentoModeEnabled = firstParameterAddress,
  portamentoRate,            // 1001
  oneVoicePerKeyModeEnabled, // 1002 aka mono
  polyphonicModeEnabled,     // 1003
  activeVoiceCount,          // 1004
  retriggerModeEnabled,      // 1005
  isRendering,               // 1006
  activeSoundFontIndex,      // 1007
  activeProgramIndex,        // 1008
  activeBankIndex,           // 1009
  activePresetIndex,         // 1010
  lastLoadFinished,          // 1011
  lastParameterAddressPlusOne
};
}
