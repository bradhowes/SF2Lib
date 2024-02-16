// Copyright © 2023 Brad Howes. All rights reserved.

#pragma once

#include <memory>
#include <Foundation/Foundation.h>
#include <CoreAudioKit/CoreAudioKit.h>
#include <string>
#include <swift/bridging>

namespace SF2 {

namespace Render::Engine { class Engine; }

/**
 Wrapper class for the SF2::Render::Engine that exposes a minimal API for Swift/C++ bridging. This perhaps better
 belongs in its own package.
 */
struct Engine
{
  /**
   Constructs a new Engine.

   @param sampleRate the sample rate to use when rendering. Note that this is not fixed and may change in the
   call to `setRenderingFormat`.
   @param voiceCount the max number of voices to allow to simultaneously render
   */
  Engine(double sampleRate, NSUInteger voiceCount);

  ~Engine() noexcept;

  /**
   Set the rendering format to be when rendering in CoreAudio infrastructure.

   @param busCount the number of busses to support. This will be at least one, and each bus will be stereo.
   @param format the format to use for rendering
   @param maxFramesToRender the max number of frames to be seen in a `processAndRender` call. A frame consists of one
   sample per channel in a bus. For stereo, N frames = 2N audio samples.
   */
  void setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender);

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
   @param index the index of the preset in the file to use
   @returns MIDI SYSEX command as a byte sequence
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSData* createLoadFileUseIndex(const std::string& path, size_t index) const noexcept;

  /**
   Obtain an `NSData` instance containing a MIDI SYSEX command that will ask the engine to use a different preset from
   the currently-loaded SF2 file (set by an earlier `createLoadFileUseIndex` request).

   @param index the index of the preset in the current file to use
   @returns MIDI SYSEX command as a byte sequence
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSData* createUseIndex(size_t index) const noexcept;

  /**
   Obtain an `NSData` instance containing MIDI command to reset the engine. This will stop playing any notes and reset
   the MIDI controllers to a known state.

   @returns MIDI command as a byte sequence
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSData* createResetCommand() const noexcept;

  /**
   Obtain an array of `NSData` instances containing MIDI commands to set the desired bank and program to use.

   @returns array of MIDI commands to be sent to engine
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSArray<NSData*>* createUseBankProgram(uint16_t bank, uint8_t program) const noexcept;

  /**
   Obtain an `NSData` instance containing MIDI command to send a channel message to the engine.

   @param channelMessage indicates the channel message to send
   @param value the value to send along with the command
   @returns MIDI command as a byte sequence
   */
  SWIFT_RETURNS_INDEPENDENT_VALUE
  NSData* createChannelMessage(uint8_t channelMessage, uint8_t value) const noexcept;

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
  std::unique_ptr<Render::Engine::Engine> impl_;
};

} // SF2::DSP namespaces
