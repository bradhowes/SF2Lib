// Copyright © 2022, 2026 Brad Howes. All rights reserved.

#pragma once

#include <array>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <queue>
#include <set>
#include <vector>

#include "DSPHeaders/EventProcessor.hpp"

#include "SF2File/IO/File.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/MIDI/GeneratorOverride.hpp"
#include "SF2Lib/Render/Engine/LiveGeneratorParameters.hpp"
#include "SF2Lib/Render/Engine/Mixer.hpp"
#include "SF2Lib/Render/Engine/OldestVoiceCollection.hpp"
#include "SF2Lib/Render/Engine/PresetsState.hpp"
#include "SF2Lib/Render/Engine/Traits.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"
#include "SF2Util/Timer.hpp"

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

 Preset and SF2 file changes can happen in two ways: via specially-crafted SysEx MIDI messages or via the Engine API. They both
 should work without any issue -- the code assumes that the render thread is always active so it uses atomic operations to
 switch to a new preset collection and/or a new preset index. There are no locks in the code so as to not block the render thread.

 The engine supports a maximum of `traits::maxVoiceCount` simultaneous voices -- these are allocated all at once in one continuous
 block of memory. However, the engine can be configured to use fewer voices at construction time via the `voiceCountLimit`. Further,
 the engine's audio rendering routine will by default limit voices when there is the threat of delaying a render cycle and causing
 an audio glitch.
 */
class Engine : public DSPHeaders::EventProcessor<Engine> {
  using super = DSPHeaders::EventProcessor<Engine>;
  friend super;

public:
  using Config = Voice::State::Config;
  using Voice = Voice::Voice;

  /// Source of the time used for the render budget, in nanoseconds. Must be monotonic and safe on the render thread.
  using Clock = uint64_t (*)() noexcept;

  /// Frames over which a voice is faded out when a render slice has already used up its time budget.
  static constexpr AUAudioFrameCount budgetFadeOutFrames = 64;

  /// Weight given to the latest measurement in the running average of the cost of rendering one voice for one frame.
  static constexpr double voiceCostSmoothing = 0.25;

  /**
   Construct new engine and its voices.

   @param sampleRate the expected sample rate to use
   @param voiceCountLimit the maximum number of individual voices to support (must be <= maxVoiceCount)
   @param renderingTimeBudgetScaling scaling to apply to the frameCount time budget (the number of nanoseconds in a render frame).
   This value runs between 0.0  and 1.0. A value of 0.0 or negative will disable the budget check. Before rendering, if the
   running estimate of the cost of the active voices exceeds the budget, the oldest voices beyond what fits are given a
   fast (5 ms) release, so the load drops without clicks. If a render call still runs out of time, each remaining voice
   is faded out over `budgetFadeOutFrames` frames and stopped.
   @param minimumNoteDurationMilliseconds the minimum duration of a note-on/note-off sequence for a voice.
   */
  Engine(Float sampleRate,
         size_t voiceCountLimit,
         double renderingTimeBudgetScaling, // = 0.85,
         size_t minimumNoteDurationMilliseconds = 10
         );

  /// Waits for queued loads to finish, then frees every preset state.
  ~Engine();

  size_t minimumNoteDurationSamples() const noexcept {
    return static_cast<size_t>(ceil(Float(minimumNoteDurationMilliseconds_) / 1000_F * sampleRate_));
  }

  /// @returns maximum number of voices available for simultaneous rendering in engine.
  size_t maxVoiceCount() const noexcept { return traits::maxVoiceCount; }

  /// @returns configured maximum number of voices available for rendering [legacy].
  size_t voiceCountLimit() const noexcept { return voiceCountLimit_; }

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
  std::string activePresetName() const;

  /// @returns the program index value for the active preset, or -1 if none is active
  int activeProgramIndex() const noexcept;

  /// @returns the bank index value of for the active preset, or -1 if none is active
  int activeBankIndex() const noexcept;

  /// @returns the current active preset index value, or -1 if none is active. NOTE: only used/reported in the AUParameterTree.
  int activePresetIndex() const noexcept;

  /// @returns the number of presets available, or 0 if none have been loaded.
  size_t presetCount() const noexcept {
    auto ptr = presetsState();
    return ptr ? ptr->size() : 0;
  }

  /// @return the number of active voices
  size_t activeVoiceCount() const noexcept { return oldestVoiceIndices_.activeVoiceCount(); }

  /**
   Render samples to the given stereo output buffers. The buffers are guaranteed to be able to hold `frameCount`
   samples, and `frameCount` will never be more than the `maxFramesToRender` value given to the `setRenderingFormat`.

   NOTE: everything from this point on should be inlined as much as possible for speed. This is executed in a real-time
   rendering thread when called via `doRendering`.

   @param mixer collection of buffers to render into
   @param frameCount number of samples to render.
   */
  void renderInto(Mixer mixer, AUAudioFrameCount frameCount) noexcept;

  /**
   API for EventProcessor. Perform rendering of audio samples using the loaded soundfont and active preset.

   **NOTE**: this runs on the real-time audio rendering thread.

   @param outputBusNumber the index of the bus being rendered
   @param outs the output buffers to write to
   @param frameCount the number of frames to render, where 1 frame is 1 sample per output buffer
   */
  void doRendering(NSInteger outputBusNumber, DSPHeaders::BusBuffers, DSPHeaders::BusBuffers outs,
                          AUAudioFrameCount frameCount) noexcept {
    // All of the work is done when working with output bus 0. If wired correctly, busses 1 and 2 will
    // hold the buffered values that were created here.
    if (outputBusNumber == 0) {
      // The voices will add their samples to the mixer so clear them here.
      outs.clear(frameCount);
      busBuffers(1).clear(frameCount);
      busBuffers(2).clear(frameCount);

      if (presetChangesPending() == 0) {
        renderInto(Mixer(outs, busBuffers(1), busBuffers(2)), frameCount);
      }
    }
  }

  /// API for EventProcessor
  AUAudioFrameCount doParameterEvent(const AUParameterEvent& event, AUAudioFrameCount duration) noexcept;

  /// API for EventProcessor. Notification that the rendering thread is running (true) or stopped (false).
  void doRenderingStateChanged(bool state) noexcept;

  /// API for EventProcessor
  void doMIDIEvent(const AUMIDIEvent& midiEvent) noexcept;

  /**
   Notify all active voices with a parameter change.

   @param index the generate to update
   */
  void notifyParameterChanged_RT(Entity::Generator::Index index) noexcept;

  /// @returns the AUParameterTree for the engine.
  AUParameterTree* parameterTree() const noexcept {
    assert(parameterTree_ !=  nullptr);
    return parameterTree_;
  }

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
   Utility class method that creates a MIDI SysEx command to load an SF2 file at the given path and to activate
   the preset at the given index. The path must be visible and accessible by the SF2Lib process if running in a sandboxed
   environment.

   @param filePath the location of the SF2 file to load
   @param presetIndex the index of the preset to activate
   @param overrides collection of SF2 generator values to apply
   @returns vector of MIDI bytes
   */
  static std::vector<uint8_t> createLoadFileUsePresetPayload(const std::string& filePath, size_t presetIndex,
                                                             const std::vector<SF2::MIDI::GeneratorOverride>& overrides);

  /**
   Utility class method that creates a MIDI SysEx command to load a SF2 file that requires a security scope to access, and to
   activate the preset at the given index.

   @param bookmark the file's bookmarkd data for the SF2 file to load
   @param presetIndex the index of the preset to activate
   @param overrides collection of SF2 generator values to apply
   @returns vector of MIDI bytes
   */
  static std::vector<uint8_t> createLoadBookmarkUsePresetPayload(const NSData* bookmark, size_t presetIndex,
                                                                 const std::vector<SF2::MIDI::GeneratorOverride>& overrides);

  /**
   Utility class method that creates a MIDI channel command to reset the engine. This stops all voices and resets the
   MIDI channel state.

   @returns array of 1 MIDI byte
   */
  static std::array<uint8_t, 1> createResetCommandPayload() noexcept;

  /**
   Utility class method that creates a collection of MIDI commands that will direct the engine to activate the preset
   at the given bank and program values.

   @param bank the bank to activate (0-16383)
   @param program the program in the bank to activate (0-127)
   @returns array of 9 MIDI bytes
   */
  static std::array<uint8_t, 9> createUseBankProgramPayload(uint16_t bank, uint8_t program) noexcept;

  /**
   Utility class method that creates a MIDI command to send the given channel message with the given value

   @param channelMessage the MIDI channel message to send
   @param value the value to provide in the channel message
   @returns array of 3 MIDI bytes
   */
  static std::array<uint8_t, 3> createChannelMessagePayload(MIDI::ControlChange channelMessage, uint8_t value = 0) noexcept;

  /// @returns array of 3 MIDI bytes with MIDI command to stop playing all notes.
  static std::array<uint8_t, 3> createAllNotesOffPayload() noexcept
  {
    return createChannelMessagePayload(MIDI::ControlChange::allNotesOff);
  }

  /// @returns array of 3 MIDI bytes with MIDI command to stop all sound output.
  static std::array<uint8_t, 3> createAllSoundOffPayload() noexcept
  {
    return createChannelMessagePayload(MIDI::ControlChange::allSoundOff);
  }

  /// @returns the counter value that tracks the number of SF2 file load requests.
  Float lastLoadFinishedCounter() const noexcept { return lastLoadFinishedCounter_; }

  /// @returns current number of preset changes pending in the work queue.
  int presetChangesPending() const noexcept { return presetChangesPending_.load(); }

  /**
   Load a soundfont file at the given path. If successful, make active the preset at the given index. This should be safe to call
   even when the audio render thread is running.

   @param path the location of the file to load. If empty, use existing preset collection.
   @param presetIndex the index of the preset to make active after loading
   @returns status indicating the success of the loading.
   */
  IO::File::LoadResponse loadFileAndPreset(std::string path, size_t presetIndex);

  /**
   Load the presets from a file descriptor and activate a specific preset.
   
   @param fd the file descriptor to read from. It is duplicated, so the caller keeps ownership and may close it as soon
   as this returns.
   @param presetIndex the preset to make active
   @returns status indicating the success of the loading.
   */
  IO::File::LoadResponse loadFileAndPreset(int fd, size_t presetIndex);

  /**
   Load a soundfont file using a secure bookmark reference. If successful, make active the preset at the given index. This should
   be safe to call even when the audio render thread is running.

   @param bookmark the encoded location of the file to load
   @param presetIndex the index of the preset to make active after loading
   */
  IO::File::LoadResponse loadBookmarkAndPreset(NSData* bookmark, size_t presetIndex);

private:
  Engine(const Engine&) = delete;
  Engine(Engine&&) = delete;

  /// @returns the most recently published presets state. Not for the render thread: use `syncPresetsState_RT`.
  PresetsState* presetsState() const noexcept { return presetsState_.load(std::memory_order_acquire); }

  /**
   Render-thread entry point to the presets state. If a new state has been published since the last call, stop all
   voices (they may reference the old state's samples) and record the new state's generation, which allows the old
   state to be freed off the render thread.

   @returns the current presets state, or nullptr if nothing has been loaded
   */
  PresetsState* syncPresetsState_RT() noexcept;

  /**
   Publish a fully prepared presets state and retire the previous one. Frees retired states the render thread no
   longer uses.

   @param state the new state to publish
   */
  void installPresetsState_WQ(PresetsState* state);

  /**
   Free retired presets states. Caller must hold `retiredMutex_`.

   @param all if true, free all of them (only safe when the render thread is not running). Otherwise free only those
   older than the generation that the render thread has acknowledged.
   */
  void reclaimRetiredPresetsStates_WQ(bool all) noexcept;

  /// Work-queue function for a program change requested by the render thread (see `changeProgram_RT`).
  static void usePresetRequest_WQ(void* context) noexcept;

  /// Common end of every preset or file change: reset live parameters, bump `lastLoadFinished`, and finally allow the
  /// render thread to render and start voices again by decrementing `presetChangesPending_`.
  void finishPresetChange_WQ() noexcept;

  static AUParameter* makeGeneratorParameter(Entity::Generator::Index index) noexcept;

  static AUParameter* makeBooleanParameter(NSString* name, ParameterAddress, bool value) noexcept;

  void parameterValueChanged(AUParameter* parameter, AUValue value) noexcept;

  AUValue provideParameterValue(AUParameter* parameter) const noexcept;

  void updateDurationParameters() noexcept;

  uint64_t timeBudgetNanoseconds(AUAudioFrameCount frameCount) const noexcept {
    return (renderingTimeBudgetScaling_ > 0.0) ? (frameCount * uint64_t(double(renderingTimeBudgetIntervalNanoseconds_) *
                                                                        renderingTimeBudgetScaling_)) : 0xFFFFFFFFFFFFFFFFL;
  }

  /**
   Create the audio unit parameter tree.
   */
  void makeTree() noexcept;

  /**
   Routine run outside of the render thread to load an SF2 file and make active a preset in it.

   @param path the file to load from
   @param index the preset to make active
   @returns IO::File::LoadResponse::OK if the loading was successful
   */
  IO::File::LoadResponse beginLoadFileAndPreset_WQ(std::string path, size_t presetIndex);

  /**
   Routine run outside of the render thread to load a secure bookmark to an SF2 file and make active a preset in it.

   @param bookmark the bookmark to load from
   @param index the preset to make active
   @returns IO::File::LoadResponse::OK if the loading was successful
   */
  IO::File::LoadResponse beginLoadBookmarkAndPreset_WQ(NSData* bookmark, size_t presetIndex);

  /**
   Finish loading from an SF2 file. Called at the conclusion of `beginLoadFileAndPreset_WQ`.

   @param path the file to load from
   @param index the preset to make active
   @returns IO::File::LoadResponse::OK if the loading was successful
   */
  IO::File::LoadResponse concludeLoad_WQ(const std::string& path, size_t index);

  /**
   Finish loading from an SF2 file. Called at the conclusion of `beginLoadBookmarkAndPreset_WQ()`.

   @param fd the file descriptor to read from
   @param index the preset to make active
   @returns IO::File::LoadResponse::OK if the loading was successful
   */
  IO::File::LoadResponse concludeLoad_WQ(int fd, size_t index);

  /**
   Active a new preset in the current preset state.

   @param presetIndex the index of the preset to activate
   */
  void usePresetWithIndex_WQ(size_t presetIndex);

  /// Reset the engine to a known state. All keys are released, all voices are off, and the MIDI channel state is reset
  /// to initial state. Used for the MIDI System Reset message (0xFF).
  void reset_RT() noexcept;

  /// Respond to MIDI Reset All Controllers (CC 121) per MIDI RP-015. See `ChannelState::resetControllers`.
  void resetAllControllers_RT() noexcept;

  /**
   Turn off all voices, making them all available for rendering.

   NOTE: this is not thread-safe. When running in a render thread, it is expected that this is only executed due to
   an incoming MIDI command.
   */
  void allOff_RT() noexcept;

  /**
   Release all keys -- all MIDI note ON events that have not seen a note OFF event. Unlike, `allOff` this does not
   stop audio.
   */
  void releaseKeys_RT() noexcept;

  /**
   Tell any voices playing the current MIDI key that the key has been released. The voice will continue to render until
   it figures out that it is done.

   NOTE: this is not thread-safe. When running in a render thread, it is expected that this is only executed due to
   an incoming MIDI command.

   @param key the MIDI key that was released
   */
  void noteOff_RT(int key) noexcept;

  /**
   Activate one or more voices to play a MIDI key with the given velocity.

   NOTE: this is not thread-safe. When running in a render thread, it is expected that this is only executed due to
   an incoming MIDI command.

   @param key the MIDI key to play
   @param velocity the MIDI velocity to play at
   */
  void noteOn_RT(int key, int velocity) noexcept;

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
   Visit each active voice with a method that accepts two parameters: a `Voice` reference.

   @param visitor the method to invoke
   */
  template <typename Visitor>
  void visitActiveVoice_RT(Visitor visitor) noexcept
  {
    auto releaseKeyState = Voice::ReleaseKeyState{minimumNoteDurationSamples(), channelState_.pedalState()};
    visitActiveVoice_RT(visitor, releaseKeyState);
  }

  /**
   Visit each active voice with a method that accepts two parameters: a `Voice` reference and a `ReleaseKeyState`
   reference that contains the current pedal state.

   @param visitor the method to invoke
   @param releaseKeyState the state of the pedal controllers
   */
  template <typename Visitor>
  void visitActiveVoice_RT(Visitor visitor, const Voice::ReleaseKeyState releaseKeyState) noexcept
  {
    for (auto pos = oldestVoiceIndices_.begin(); pos != oldestVoiceIndices_.end(); ) {
      auto voiceIndex = *pos;
      auto& voice{voices_[voiceIndex]};
      if (!voice.isActive()) {
        pos = oldestVoiceIndices_.voiceRelease(voiceIndex);
      } else {
        visitor(voice, releaseKeyState);
        ++pos;
      }
    }
  }

  void bumpLastLoadFinished_WQ() noexcept;

  void initialize(Float sampleRate) noexcept;

  void stopAllExclusiveVoices_RT(int exclusiveClass) noexcept;

  void stopSameKeyVoices_RT(int eventKey) noexcept;

  /**
   Start a voice for the given configuration.

   @param config the zones to use
   @returns the index of the voice that was started, or `Voice::noPartner` if none was
   */
  size_t startVoice_RT(const Config& config) noexcept;

  /**
   Link the voices of any stereo pairs among the configs of a note-on (SF2.01 7.10), so that they render in lockstep
   with the right sample's pitch.

   @param configs the configs that `Preset::find` returned
   @param voiceIndices the voice started for each config (`Voice::noPartner` if none)
   */
  void linkStereoPairs_RT(const Preset::ConfigCollection& configs, const std::array<size_t, Preset::maxConfigsPerNote>&
                          voiceIndices) noexcept;

  /// Unlink the given voice and its stereo partner, if it has one.
  void unlinkStereoPartner_RT(size_t voiceIndex) noexcept;

  OldestVoiceCollection::iterator stopVoice_RT(size_t voiceIndex) noexcept;

  /**
   Give a fast release to the oldest voices that would not fit in the time budget, going by the running average of the
   cost of rendering one voice for one frame. The newest voice is always kept. Voices that are already fast-releasing
   count towards the load (they are still rendered) but are not released again.

   @param frameCount the number of frames in the render slice
   @param timeBudget the time available for the slice in nanoseconds
   */
  void shedVoicesOverBudget_RT(AUAudioFrameCount frameCount, uint64_t timeBudget) noexcept;

  /// Record the active voice count for `publishActiveVoiceCount`. Lock-free, so safe on the render thread.
  void shareActiveVoiceCount_RT() noexcept {
    activeVoiceCountShared_.store(uint32_t(oldestVoiceIndices_.activeVoiceCount()), std::memory_order_relaxed);
  }

  /**
   Set the `activeVoiceCount` parameter from the value shared by the render thread, if it changed, which notifies the
   parameter's observers. Runs on `activeVoiceCountQueue_` (never on the render thread: it uses Objective-C).
   */
  void publishActiveVoiceCount() noexcept;

  /// Start the timer that calls `publishActiveVoiceCount` (when rendering starts).
  void startPublishingActiveVoiceCount() noexcept;

  /// Stop the timer, then publish the final count (when rendering stops, and on destruction).
  void stopPublishingActiveVoiceCount() noexcept;

  void notifyActiveVoicesChannelStateChanged_RT() noexcept;

  void processChannelMessage_RT(MIDI::ControlChange cc, uint8_t value) noexcept;

  void processControlChange_RT(MIDI::ControlChange cc, uint8_t value) noexcept;

  void changeProgram_RT(uint8_t program) noexcept;

  /**
   Hand a "load file/bookmark and preset" SysEx message to the work queue. Runs on the render thread, so it only
   copies the raw bytes into a free preallocated `SysExRequest` slot; all parsing and decoding happens in
   `processSysExRequest_WQ`.

   @param midiEvent the SysEx event (already known to be addressed to us and to end with EOX)
   @returns true if the request was queued
   */
  bool queueSysExRequest_RT(const AUMIDIEvent& midiEvent) noexcept;

  /// Work-queue function that parses and runs a queued SysEx request. `context` is the `SysExRequest`.
  static void processSysExRequest_WQ(void* context) noexcept;

  /// Parse a queued SysEx request and start the load it describes.
  void processSysExRequest_WQ(const uint8_t* bytes, size_t length);


  void applySostenutoPedal_RT() noexcept;

  /// Release the voices whose key-up was postponed by a pedal that has just been lifted. Held keys keep sounding.
  void applyPedals_RT() noexcept;

  Float sampleRate_;
  size_t minimumNoteDurationMilliseconds_{0};

  MIDI::ChannelState channelState_{};
  LiveGeneratorParameters parameters_{};

  AUParameterTree* parameterTree_;
  std::array<Voice, traits::maxVoiceCount> voices_{};
  OldestVoiceCollection oldestVoiceIndices_;
  std::size_t voiceCountLimit_;

  std::atomic<PresetsState*> presetsState_{nullptr};

  /// Generation for the next presets state (loads can come from the work queue or from API callers)
  std::atomic<uint64_t> nextGeneration_{1};

  /// Generation of the presets state the render thread is using. Written only by the render thread.
  std::atomic<uint64_t> renderGeneration_{0};

  /// Preset index for the latest program change, read by `usePresetRequest_WQ`
  std::atomic<size_t> requestedPresetIndex_{0};

  /// A SysEx message copied off the render thread. Bookmarks and paths are Base64-encoded, so 8 KB is ample.
  struct SysExRequest {
    static constexpr size_t capacity = 8 * 1024;
    Engine* engine{nullptr};
    std::atomic<bool> busy{false};
    size_t length{0};
    std::array<uint8_t, capacity> bytes{};
  };

  /// Preallocated SysEx slots. A request that finds them all busy is dropped.
  std::array<SysExRequest, 4> sysExRequests_{};

  /// Presets states that have been replaced and are waiting until the render thread no longer uses them
  std::mutex retiredMutex_;
  std::vector<PresetsState*> retired_;

  std::atomic<int> presetChangesPending_{0};

  /// How often the active voice count is published to the `activeVoiceCount` parameter while rendering.
  static constexpr int64_t activeVoiceCountPublishIntervalNanoseconds = 50 * NSEC_PER_MSEC;

  /// Active voice count written by the render thread (lock-free) and read by `publishActiveVoiceCount`.
  std::atomic<uint32_t> activeVoiceCountShared_{0};

  /// The last value given to the `activeVoiceCount` parameter. Only used on `activeVoiceCountQueue_`.
  uint32_t activeVoiceCountPublished_{0};

  /// Serial queue and timer that publish the active voice count while rendering, off the render thread.
  dispatch_queue_t activeVoiceCountQueue_;
  dispatch_source_t activeVoiceCountTimer_{nullptr};

  size_t portamentoRateMillisecondsPerSemitone_{100};

  PhonicMode phonicMode_{PhonicMode::poly};
  bool oneVoicePerKeyModeEnabled_{false};
  bool portamentoModeEnabled_{false};
  bool retriggerModeEnabled_{true};

  os_signpost_id_t renderSignpost_;
  os_signpost_id_t noteOnSignpost_;
  os_signpost_id_t noteOffSignpost_;
  os_signpost_id_t startVoiceSignpost_;
  os_signpost_id_t stopVoiceSignpost_;

  AUValue lastLoadFinishedCounter_{traits::minLastLoadFinished};
  std::vector<AUValue> durationBuckets_;

  uint64_t renderingTimeBudgetIntervalNanoseconds_;
  double renderingTimeBudgetScaling_;
  Clock clock_{&Utils::Timer::now};
  double averageVoiceFrameNanoseconds_{0.0};

  /// Counts calls to `renderInto`, so that a stereo pair rendered together is not rendered again in the same slice.
  uint64_t renderSlice_{0};

  dispatch_queue_t workQueue_;

  friend struct ::TestEngineHarness;
  friend class Parameters;
};

} // end namespace SF2::Render
