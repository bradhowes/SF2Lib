// Copyright © 2023 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <memory>
#include <string>
#include <vector>

#include <Foundation/Foundation.h>
#include <CoreAudioKit/CoreAudioKit.h>
#include <swift/bridging>

/**
 Umbrella header for the Engine module to use with Swift via interoperability mode.
 */

namespace SF2 {
namespace Entity { class Preset; }
namespace IO { class File; }
namespace Render { namespace Engine { class Engine; } }
}

/**
 Wrapper class for the SF2::Render::Engine that exposes a minimal API for Swift/C++ bridging. This perhaps better
 belongs in its own package.
 */
struct SF2Engine
{
  /**
   Constructs a new Engine.

   @param sampleRate the sample rate to use when rendering. Note that this is not fixed and may change in the
   call to `setRenderingFormat`.
   @param voiceCount the max number of voices to allow to simultaneously render
   */
  SF2Engine(double sampleRate, NSUInteger voiceCount);

  ~SF2Engine() noexcept;

  /**
   Set the rendering format to be when rendering in CoreAudio infrastructure. After returning from this call,
   the engine will be ready to process and render samples -- though no sound will be emitted until a SF2 file
   is installed and a preset is chosen.

   @param busCount the number of busses to support. This will be at least one, and each bus will be stereo.
   @param format the format to use for rendering
   @param maxFramesToRender the max number of frames to be seen in a `processAndRender` call. A frame consists of one
   sample per channel in a bus. For stereo, N frames = 2N audio samples.
   @returns `true` if engine can start rendering
   */
  bool setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender);

  /**
   Request to render samples. May be called on a real-time thread by the CoreAudio framework. Note that
   `setRenderingFormat` will be called before the first call to this method.`

   @param timestamp the point in time for the rendering to take place
   @param frameCount the number of frames to render
   @param outputBusNumber the bus that is being rendered to
   @param output the audio buffer to write to. Note that this might not contain the actual samples buffers to use
   @param realtimeEventListHead the list of events to process in order of timestamps when they should take place
   @param pullInputBlock for an effect, this will be called to obtain samples to operate on. For the SF2 engine, this
   is ignored.
   @returns result of the call. Should be `noErr` unless there is an issue with one of the parameters and the rendering
   could not take place.
   */
  AUAudioUnitStatus processAndRender(const AudioTimeStamp* timestamp, UInt32 frameCount, NSInteger outputBusNumber,
                                     AudioBufferList* output, const AURenderEvent* realtimeEventListHead,
                                     AURenderPullInputBlock pullInputBlock);

  /**
   Obtain the name of the active preset being used by the engine. This will be an empty string ("") for the case where
   there is no active preset.

   @returns preset name or ""
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  std::string activePresetName() const noexcept;

  /// @returns current number of active voices
  size_t activeVoiceCount() const noexcept;

  /**
   Obtain an `NSData` instance containing a MIDI SYSEX command that can be sent to load an SF2 file and use a given
   preset. This should be sent to the engine via a MIDI control connection; this method only creates the bytes to send.

   @param path the full path of the SF2 file to load
   @param preset the index of the preset in the file to use
   @returns MIDI SYSEX command as a byte sequence
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  static std::vector<uint8_t> createLoadFileUsePreset(const std::string& path, size_t preset) noexcept;

  /**
   Obtain an `NSData` instance containing a MIDI SYSEX command that will ask the engine to use a different preset from
   the currently-loaded SF2 file (set by an earlier `createLoadFileUseIndex` request).

   @param preset the index of the preset in the current file to use
   @returns MIDI SYSEX command as a byte sequence
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  static std::array<uint8_t, 6> createUsePreset(size_t preset) noexcept;

  /**
   Obtain an `NSData` instance containing MIDI command to reset the engine. This will stop playing any notes and reset
   the MIDI controllers to a known state.

   @returns MIDI command as a byte sequence
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  static std::array<uint8_t, 1> createResetCommand() noexcept;

  /**
   Obtain an array of `NSData` instances containing MIDI commands to set the desired bank and program to use.

   @returns array of MIDI commands to be sent to engine
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  static std::array<uint8_t, 8> createUseBankProgram(uint16_t bank, uint8_t program) noexcept;

  /**
   Obtain an `NSData` instance containing MIDI command to send a channel message to the engine.

   @param channelMessage indicates the channel message to send
   @param value the value to send along with the command
   @returns MIDI command as a byte sequence
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  static std::array<uint8_t, 3> createChannelMessage(uint8_t channelMessage, uint8_t value) noexcept;

  SWIFT_RETURNS_INDEPENDENT_VALUE
  static std::array<uint8_t, 3> createAllNotesOff() noexcept;

  SWIFT_RETURNS_INDEPENDENT_VALUE
  static std::array<uint8_t, 3> createAllSoundOff() noexcept;

  /// @returns true if the monophonic mode is enabled
  bool monophonicModeEnabled() const noexcept;
  /// @returns true if the polyphonic mode is enabled
  bool polyphonicModeEnabled() const noexcept;
  /// @returns true if portamento mode is enabled
  bool portamentoModeEnabled() const noexcept;
  /// @returns true if "one-voice-per-key" mode is enabled.
  bool oneVoicePerKeyModeEnabled() const noexcept;
  /// @returns true if `retrigger` mode is enabled.
  bool retriggerModeEnabled() const noexcept;

private:
  std::shared_ptr<SF2::Render::Engine::Engine> impl_;
};

struct SF2PresetInfo {

  SF2PresetInfo(std::string name, int bank, int program) : name_{name}, bank_{bank}, program_{program} {}

  SF2PresetInfo(const SF2::Entity::Preset& preset);

  SWIFT_RETURNS_INDEPENDENT_VALUE
  std::string name() const noexcept { return name_; }

  int bank() const noexcept { return bank_; }

  int program() const noexcept { return program_; }

private:
  std::string name_;
  int bank_;
  int program_;
};

/**
 A light-weight SF2 loader that provides meta data and preset information. It does not load samples nor does it
 create the render entities such as the preset and instrument zones.
 */
struct SF2FileInfo
{
  SF2FileInfo(const char* path);

  SF2FileInfo(std::string path);

  ~SF2FileInfo();

  bool load();

  /// @returns the embedded name in the file
  SWIFT_RETURNS_INDEPENDENT_VALUE
  std::string embeddedName() const noexcept;

  /// @returns the embedded author name in the file
  SWIFT_RETURNS_INDEPENDENT_VALUE
  std::string embeddedAuthor() const noexcept;

  /// @returns any embedded comment in the file
  SWIFT_RETURNS_INDEPENDENT_VALUE
  std::string embeddedComment() const noexcept;

  /// @returns any embedded copyright notice in the file
  SWIFT_RETURNS_INDEPENDENT_VALUE
  std::string embeddedCopyright() const noexcept;

  size_t size() const noexcept;

  SWIFT_RETURNS_INDEPENDENT_VALUE
  SF2PresetInfo operator[](size_t index) const noexcept;

private:
  std::shared_ptr<SF2::IO::File> impl_;
};
