// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <functional>
#include <map>
#include <memory>
#include <queue>
#include <set>
#include <vector>

#include "SF2Lib/DSPHeaders/EventProcessor.hpp"

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/Engine/Mixer.hpp"
#include "SF2Lib/Render/Engine/OldestVoiceCollection.hpp"
#include "SF2Lib/Render/Engine/Parameters.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

struct TestEngineHarness;

namespace SF2::Render::Engine {

/**
 Engine that generates audio from SF2 files due to incoming MIDI signals. Maintains a collection of voices created at
 construction time. A Voice generates samples based on the configuration it is given from a Preset.

 Note that a major design goal is to keep from allocating any memory while a render thread is running and generating
 samples. This also implies that all communications with the engine while rendering (eg MIDI events or real-time
 parameter changes should be done with care. For the AUv3 use-case, this is handled by the `EventProcessor` base class
 and the AUv3 API. MIDI events and parameter changes are scheduled using dedicated APIs and the render thread sees them
 during a render request.
 */
class Engine : public DSPHeaders::EventProcessor<Engine> {
  using super = DSPHeaders::EventProcessor<Engine>;
  friend super;

public:
  /// Maximum number of voices that can be supported by the engine
  static inline constexpr size_t maxVoiceCount = 128;

  using Config = Voice::State::Config;
  using Voice = Voice::Voice;
  using Interpolator = Render::Voice::Sample::Interpolator;

  /**
   Construct new engine and its voices.

   @param sampleRate the expected sample rate to use
   @param voiceCount the maximum number of individual voices to support (must be <= maxVoiceCount)
   @param interpolator the type of interpolation to use when rendering samples
   @param minimumNoteDurationMilliseconds the minimum duration of a note-on/note-off sequence for a voice.
   */
  Engine(Float sampleRate, size_t voiceCount, Interpolator interpolator,
         size_t minimumNoteDurationMilliseconds = 10) noexcept;

  size_t minimumNoteDurationSamples() const noexcept
  {
    return static_cast<size_t>(ceil(minimumNoteDurationMilliseconds_ / 1000_F * sampleRate_));
  }

  /// @returns maximum number of voices available for simultaneous rendering
  size_t voiceCount() const noexcept { return voices_.size(); }

  /**
   Update kernel and buffers to support the given format and channel count

   @param format the audio format to render
   @param maxFramesToRender the maximum number of samples we will be asked to render in one go
   */
  void setRenderingFormat(NSInteger busCount, AVAudioFormat* format, AUAudioFrameCount maxFramesToRender) noexcept;

  /// @returns the current sample rate
  Float sampleRate() const noexcept { return sampleRate_; }

  /// @returns the MIDI channel state assigned to the engine
  MIDI::ChannelState& channelState() noexcept { return channelState_; }

  /// @returns the MIDI channel state assigned to the engine
  const MIDI::ChannelState& channelState() const noexcept { return channelState_; }

  /// @returns true if there is an active preset
  bool hasActivePreset() const noexcept;

  /// @returns name of the active preset or empty string if none is active
  std::string activePresetName() const noexcept;

  /// @returns number of presets available.
  size_t presetCount() const noexcept { return presets_.size(); }

  /// @return the number of active voices
  size_t activeVoiceCount() const noexcept { return oldestVoiceIndices_.active(); }

  /**
   Render samples to the given stereo output buffers. The buffers are guaranteed to be able to hold `frameCount`
   samples, and `frameCount` will never be more than the `maxFramesToRender` value given to the `setRenderingFormat`.

   NOTE: everything from this point on should be inlined as much as possible for speed. This is executed in a real-time
   rendering thread.

   @param mixer collection of buffers to render into
   @param frameCount number of samples to render.
   */
  void renderInto(Mixer mixer, AUAudioFrameCount frameCount) noexcept
  {
    for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
      auto voiceIndex = *pos;
      auto& voice{voices_[voiceIndex]};
      if (voice.isActive()) {
        voice.renderInto(mixer, frameCount);
      }
      if (voice.isDone()) {
        pos = oldestVoiceIndices_.voiceOff(voiceIndex);
      } else {
        ++pos;
      }
    }
  }

  /// API for EventProcessor
  AUAudioFrameCount doParameterEvent(const AUParameterEvent& event, AUAudioFrameCount duration) noexcept;

  /// API for EventProcessor
  void doRenderingStateChanged(bool state) noexcept { if (!state) allOff(); }

  /// API for EventProcessor
  void doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept;

  /// API for EventProcessor
  void doRendering(NSInteger outputBusNumber, DSPHeaders::BusBuffers, DSPHeaders::BusBuffers outs,
                   AUAudioFrameCount frameCount) noexcept
  {
    if (outputBusNumber == 0) {
      // All of the work is done when working with output bus 0. If wired correctly, busses 1 and 2 will
      // use the buffered values that were created here.
      renderInto(Mixer(outs, busBuffers(1), busBuffers(2)), frameCount);
    }
  }

  /**
   Notify all active voices with a parameter change.

   @param index the generate to update
   */
  void notifyParameterChanged(Entity::Generator::Index index) noexcept;

  /// @returns the AUParameterTree for the engine.
  AUParameterTree* parameterTree() const noexcept { return parameters_.parameterTree(); }

  /// @returns true if portamento mode is enabled
  bool portamentoModeEnabled() const noexcept { return portamentoModeEnabled_; }

  /// @returns the rate of change from one note to another expressed as milliseconds per semitone change
  size_t portamentoRate() const noexcept { return portamentoRateMillisecondsPerSemitone_; }

  /// @returns true if only one voice will play at the same time for the same MIDI key
  bool oneVoicePerKeyModeEnabled() const noexcept { return oneVoicePerKeyModeEnabled_; }

  /// @returns true if a new note ON for the same key will use a new envelopes or will simply inherit the active one.
  bool retriggerModeEnabled() const noexcept { return retriggerModeEnabled_; }

  /// @returns true if Engine is in monophonic mode
  bool monophonicModeEnabled() const noexcept { return phonicMode_ == PhonicMode::mono; }

  /// @returns true if Engine is in polyphonic mode (default)
  bool polyphonicModeEnabled() const noexcept { return phonicMode_ == PhonicMode::poly; }

  /**
   Utility class method that creates a MIDI SysEx command to load a SF2 file at the given path and to activate
   the preset at the given index.

   @param path the location of the SF2 file to load
   @param preset the index of the preset to activate
   @returns array of MIDI bytes
   */
  static std::vector<uint8_t> createLoadFileUsePreset(const std::string& path, size_t preset) noexcept;

  /**
   Utility class method that creates a MIDI SysEx command to activate the preset at the given index in the
   currently loaded SF2 file. This is the same as `createLoadSysExec` with a zero-length string.

   @param preset the index of the preset to activate
   @returns array of MIDI bytes
   */
  static std::vector<uint8_t> createUsePreset(size_t preset) noexcept;

  /**
   Utility class method that creates a MIDI channel command to reset the engine. This stops all voices and resets the
   MIDI channel state.

   @returns array of MIDI bytes
   */
  static std::vector<uint8_t> createResetCommand() noexcept;

  /**
   Utility class method that creates a collection of MIDI commands that will direct the engine to activate the preset
   at the given bank and program values.

   @param bank the bank to activate (0-16383)
   @param program the program in the bank to activate (0-127)
   @returns array of an array of MIDI bytes
   */
  static std::vector<std::vector<uint8_t>> createUseBankProgram(uint16_t bank, uint8_t program) noexcept;

  /**
   Utility class method that creates a MIDI command to send the given channel message with the given value

   @param channelMessage the MIDI channel message to send
   @param value the value to provide in the channel message
   @returns array of MIDI bytes
   */
  static std::vector<uint8_t> createChannelMessage(MIDI::ControlChange channelMessage, uint8_t value) noexcept;

private:

  /**
   Load the presets from an SF2 file and activate one. NOTE: this is not thread-safe. When running in a render thread,
   one should use the special MIDI system-exclusive command to perform a load. See comment in `doMIDIEvent`.

   @param path the file to load from
   @param index the preset to make active
   @returns true if the loading was successful
   */
  IO::File::LoadResponse load(const std::string& path, size_t index) noexcept;

  /**
   Activate the preset at the given index.

   NOTE: this is not thread-safe. When running in a render thread, it is expected that this is only executed due to
   an incoming MIDI command.

   @param index the preset to use
   */
  void usePresetWithIndex(size_t index);

  /**
   Activate the preset at the given bank/program.

   NOTE: this is not thread-safe. When running in a render thread, it is expected that this is only executed due to
   an incoming MIDI command.

   @param bank the bank to use
   @param program the program in the bank to use
   */
  void usePresetWithBankProgram(uint16_t bank, uint16_t program);

  /// Reset the engine to a known state. All keys are released, all voices are off, and the MIDI channel state is reset
  /// to initial state.
  void reset() noexcept;

  /**
   Turn off all voices, making them all available for rendering. 

   NOTE: this is not thread-safe. When running in a render thread, it is expected that this is only executed due to
   an incoming MIDI command.
   */
  void allOff() noexcept;

  /**
   Release all keys -- all MIDI note ON events that have not seen a note OFF event. Unlike, `allOff` this does not
   stop audio.
   */
  void releaseKeys() noexcept;
  
  /**
   Tell any voices playing the current MIDI key that the key has been released. The voice will continue to render until
   it figures out that it is done.

   NOTE: this is not thread-safe. When running in a render thread, it is expected that this is only executed due to
   an incoming MIDI command.

   @param key the MIDI key that was released
   */
  void noteOff(int key) noexcept;

  /**
   Activate one or more voices to play a MIDI key with the given velocity.

   NOTE: this is not thread-safe. When running in a render thread, it is expected that this is only executed due to
   an incoming MIDI command.

   @param key the MIDI key to play
   @param velocity the MIDI velocity to play at
   */
  void noteOn(int key, int velocity) noexcept;

  /**
   Set the portamento (glissando/glide) mode. Note that this is only applicable in monophonic mode.

   NOTE: only settable via AUParameter change

   @param value enable portamento mode if true
   */
  void setPortamentoModeEnabled(bool value) noexcept { portamentoModeEnabled_ = value; }

  /**
   Set the rate at which the note transitions from the old pitch to the new pitch. This is expressed as milliseconds
   per semitone.

   NOTE: only settable via AUParameter change

   @param value the rate in milliseconds
   */
  void setPortamentoRate(size_t value) noexcept { portamentoRateMillisecondsPerSemitone_ = value; }

  /**
   Set the "one voice per key" mode. When enabled, playing the same MIDI note will stop any active previous note. When
   disabled, the engine will allow multiple voices to play simultaneously for the same MIDI note.

   NOTE: only settable via AUParameter change

   @param value enable if true
   */
  void setOneVoicePerKeyModeEnabled(bool value) noexcept { oneVoicePerKeyModeEnabled_ = value; }

  /**
   Controls the retriggering of the volume and modulation envelopes when pressing the same key.

   NOTE: only settable via AUParameter change

   @param value enable if true
   */
  void setRetriggerModeEnabled(bool value) noexcept { retriggerModeEnabled_ = value; }

  /// The note playing mode of the engine.
  enum class PhonicMode
  {
    mono = 0,
    poly = 1
  };

  /**
   Set the "phonic" mode of the synthesizer.

   NOTE: only settable via AUParameter change or MIDI channel message

   @param mode the mode to enter
   */
  void setPhonicMode(PhonicMode mode) noexcept { phonicMode_ = mode; }

  /**
   Visit each active voice with a method that accepts two parameters: a `Voice` reference and a `ReleaseKeyState`
   reference that contains the current pedal state.

   @param visitor the method to invoke
   */
  template <typename Visitor>
  void visitActiveVoice(Visitor visitor) noexcept
  {
    auto releaseKeyState = Voice::ReleaseKeyState{minimumNoteDurationSamples(), channelState_.pedalState()};
    visitActiveVoice(visitor, releaseKeyState);
  }

  /**
   Visit each active voice with a method that accepts two parameters: a `Voice` reference and a `ReleaseKeyState`
   reference that contains the current pedal state.

   @param visitor the method to invoke
   @param releaseKeyState the state of the pedal controllers
   */
  template <typename Visitor>
  void visitActiveVoice(Visitor visitor, const Voice::ReleaseKeyState releaseKeyState) noexcept
  {
    for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
      auto voiceIndex = *pos;
      auto& voice{voices_[voiceIndex]};
      if (!voice.isActive()) {
        pos = oldestVoiceIndices_.voiceOff(voiceIndex);
      } else {
        visitor(voice, releaseKeyState);
        ++pos;
      }
    }
  }

  void initialize(Float sampleRate) noexcept;

  void stopAllExclusiveVoices(int exclusiveClass) noexcept;

  void stopSameKeyVoices(int eventKey) noexcept;

  void startVoice(const Config& config) noexcept;

  OldestVoiceCollection<maxVoiceCount>::iterator stopVoice(size_t voiceIndex) noexcept;

  void notifyActiveVoicesChannelStateChanged() noexcept;

  void processChannelMessage(MIDI::ControlChange cc, uint8_t value) noexcept;

  void processControlChange(MIDI::ControlChange cc, uint8_t value) noexcept;

  void changeProgram(uint8_t program) noexcept;

  void loadFromMIDI(const AUMIDIEvent& midiEvent) noexcept;

  void applySostenutoPedal() noexcept;

  void applyPedals() noexcept;

  Float sampleRate_;
  size_t minimumNoteDurationMilliseconds_{0};

  MIDI::ChannelState channelState_{};
  Parameters parameters_;

  std::vector<Voice> voices_{};
  OldestVoiceCollection<maxVoiceCount> oldestVoiceIndices_;

  std::unique_ptr<IO::File> file_{};
  PresetCollection presets_{};
  size_t activePreset_{0};

  size_t portamentoRateMillisecondsPerSemitone_{100};
  std::atomic<PhonicMode> phonicMode_{PhonicMode::poly};

  std::atomic<bool> oneVoicePerKeyModeEnabled_{false};
  std::atomic<bool> portamentoModeEnabled_{false};
  std::atomic<bool> retriggerModeEnabled_{true};

  os_log_t log_;
  os_signpost_id_t renderSignpost_;
  os_signpost_id_t noteOnSignpost_;
  os_signpost_id_t noteOffSignpost_;
  os_signpost_id_t startVoiceSignpost_;
  os_signpost_id_t stopVoiceSignpost_;

  friend struct ::TestEngineHarness;
  friend class Parameters;
};

} // end namespace SF2::Render
