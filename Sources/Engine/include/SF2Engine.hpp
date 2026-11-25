// Copyright © 2023, 2025, 2026 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <memory>
#include <string>
#include <vector>

#include <Foundation/Foundation.h>
#include <CoreAudioKit/CoreAudioKit.h>
#include <SF2File/Entity/Generator/Index.hpp>
#include <SF2File/IO/LoadResponse.hpp>
#include <SF2Lib/Render/Engine/ParameterAddress.hpp>

#include <swift/bridging>

/**
 Umbrella header for the Engine module to use with Swift via interoperability mode. It deliberately includes only the
 small headers that its API needs (`LoadResponse`, generator indices and parameter addresses), so that Swift does not
 import the internal parsing and rendering API.
 */

namespace SF2 {
namespace Render { namespace Engine { class Engine; } }
}

/**
 Wrapper class for the SF2::Render::Engine that exposes a minimal API for Swift/C++ bridging. Note that with this
 wrapper, there is no direct way to manipulate the held SF2::Render::Engine::Engine entity. The expectation is that
 an instance of SF2Engine will be held within an AUv3 plugin component, which can receive changes via its
 AUParameterTree or via MIDI commands. This class exposes various `create` methods that return proper MIDI v1 commands.
 In particular, the `createLoadFileUsePresetPayload` returns a MIDI SysEx sequence that indicates an SF2 file to load
 and a preset in that file to use.

 An SF2Engine is a handle: copies (in C++ or Swift) share the same engine, like a `shared_ptr`. Every method is `const`
 because none of them changes the handle itself, only the engine behind it. Swift therefore imports them all as
 non-mutating, so they can be called on a `let` and do not take exclusive access to the variable holding the engine.
 */
struct SWIFT_ESCAPABLE SWIFT_SELF_CONTAINED SF2Engine
{
  /**
   Constructs a new Engine.
   */
  SF2Engine();

  /// @returns the largest voice count that an engine supports
  static size_t maxVoiceCount() noexcept;

  /// @returns the number of voices this engine was created with, after clamping
  size_t voiceCountLimit() const noexcept;

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
  bool setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender) const noexcept;

  /**
   Obtain a render block to be used to invoke the `processAndRender` method below. The block holds its own reference
   to the engine, so it stays valid even if every `SF2Engine` copy is destroyed first. If the block is the last
   holder, releasing it destroys the engine, so do not release it on the render thread.
   */
  AUInternalRenderBlock getRenderBlock() const noexcept SWIFT_RETURNS_INDEPENDENT_VALUE;

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
                                     AURenderPullInputBlock pullInputBlock) const noexcept;

  /**
   Obtain the name of the active preset being used by the engine. This will be an empty string ("") for the case where
   there is no active preset.

   @returns preset name or ""
   */
  std::string activePresetName() const;

  /// @returns current number of active voices
  size_t activeVoiceCount() const noexcept;

  AUParameterTree* getParameterTree() const noexcept;

  /**
   Obtain MIDI payload containing a MIDI SYSEX command that can be sent to load an SF2 file and use a given
   preset. This should be sent to the engine via a MIDI control connection; this method only creates the bytes to send.

   @param filePath the full path of the SF2 file to load
   @param presetIndex the index of the preset in the file to use
   @returns MIDI SYSEX command as a byte sequence
   */
  static std::vector<uint8_t> createLoadFileUsePresetPayload(std::string filePath, size_t presetIndex);

  /**
   Load a soundfont file at the given path. If successful, make active the preset at the given index.

   @param path the location of the file to load
   @param presetIndex the index of the preset to make active after loading
   */
  SF2::IO::LoadResponse loadFileAndPreset(std::string path, size_t presetIndex) const;

  /**
   Load a soundfont from the given file descriptor. If successful, make active the preset at the given index.

   @param fd the file descriptor to read from. It is duplicated, so the caller keeps ownership and may close it as soon
   as this returns.
   @param presetIndex the index of the preset to make active after loading
   */
  SF2::IO::LoadResponse loadFileAndPreset(int fd, size_t presetIndex) const;

  /**
   Obtain MIDI payload containing a MIDI SYSEX command that can be sent to load an SF2 file and use a given
   preset. This should be sent to the engine via a MIDI control connection; this method only creates the bytes to send.

   @param bookmark the bookmark data for the URL to load
   @param presetIndex the index of the preset in the file to use
   @returns MIDI SYSEX command as a byte sequence
   */
  static std::vector<uint8_t> createLoadBookmarkUsePresetPayload(NSData* bookmark, size_t presetIndex);

  /**
   Load a soundfont file using a bookmark. If successful, make active the preset at the given index.

   NOTE: this should only be invoked when there is no rendering activity. Otherwise, this change should be done using a
   SysEx MIDI command created by ``createLoadBookmarkUsePresetPayload`` sent to the MIDI event scheduling block.

   @param bookmark the encoded location of the file to load
   @param presetIndex the index of the preset to make active after loading
   */
  SF2::IO::LoadResponse loadBookmarkAndPreset(NSData* bookmark, size_t presetIndex) const;

  /**
   Obtain MIDI payload containing MIDI command to reset the engine. This will stop playing any notes and reset
   the MIDI controllers to a known state.

   @returns MIDI command as a byte sequence
   */
  static std::array<uint8_t, 1> createResetCommandPayload() noexcept;

  /**
   Obtain MIDI payload containing MIDI commands to set the desired bank and program to use.

   @returns array of MIDI commands to be sent to engine
   */
  static std::array<uint8_t, 9> createUseBankProgramPayload(uint16_t bank, uint8_t program) noexcept;

  /**
   Obtain MIDI payload containing MIDI command to send a channel message to the engine.

   @param channelMessage indicates the channel message to send
   @param value the value to send along with the command
   @returns MIDI command as a byte sequence
   */
  static std::array<uint8_t, 3> createChannelMessagePayload(uint8_t channelMessage, uint8_t value) noexcept;

  /**
   Obtain MIDI payload containing MIDI command to stop any and all active notes.

   @returns MIDI command as a byte sequence
   */
  static std::array<uint8_t, 3> createAllNotesOffPayload() noexcept;

  /**
   Obtain MIDI payload containing MIDI command to stop all sound rendering.

   @returns MIDI command as a byte sequence
   */
  static std::array<uint8_t, 3> createAllSoundOffPayload() noexcept;

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
  // Use of shared_ptr is on purpose in order to hide the internal API.
  std::shared_ptr<SF2::Render::Engine::Engine> impl_;

  friend struct SF2EngineTestAccess;
};
