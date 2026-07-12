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
  /// Number of voices currently rendering audio samples
  activeVoiceCount,          // 1004 (read-only)
  retriggerModeEnabled,      // 1005
  /// True (1.0) if the component is rendering audio samples
  isRendering,               // 1006 (read-only)
  activeSoundFontIndex,      // 1007 (read-only) (not used)
  activeProgramIndex,        // 1008 (read-only)
  activeBankIndex,           // 1009 (read-only)
  activePresetIndex,         // 1010 (read-only)
  /// Counter that increases each time a new preset is loaded -- signals when the change has taken place.
  lastLoadFinished,          // 1011 (read-only)
  lastParameterAddressPlusOne
};
}
