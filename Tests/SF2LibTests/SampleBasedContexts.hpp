// Copyright © 2022 Brad Howes. All rights reserved.
//

#pragma once

#include <memory>

#include <XCTest/XCTest.h>

#include "SF2Lib/IO/File.hpp"
#include "SF2Lib/Render/Preset.hpp"
// #include "SF2Lib/Render/Voice/State/State.hpp"

struct PresetTestContextBase
{
  inline static SF2::Float epsilon = 1.0e-8;
  static NSURL* getUrl(int urlIndex);
};

/**
 Test harness for working with presets in SF2 files. Lazily creates test contexts. The template parameter UrlIndex is
 an integer index into `SF2Files.allResources` which is a list of SF2 files that are available to read.
 */
template <int UrlIndex>
struct PresetTestContext : PresetTestContextBase
{
  PresetTestContext(size_t presetIndex = 0, SF2::Float sampleRate = 48000.0) :
  sampleRate_{sampleRate}, presetIndex_{presetIndex}
  {}

  /// @return URL path to the SF2 file
  const NSURL* url() const { return getUrl(UrlIndex); }

  /// @return open file descriptor to the SF2 file
  int fd() const { return ::open(url().path.UTF8String, O_RDONLY); }

  /// @return reference to File that loaded the SF2 file.
  const SF2::IO::File& file() const { return state()->file_; }

  /// @return reference to Preset from SF2 file.
  const SF2::Render::Preset& preset() const { return state()->preset_; }

  SF2::Render::Voice::State::State makeState(const SF2::Render::Voice::State::Config& config) const {
    SF2::Render::Voice::State::State state(sampleRate_, channelState_);
    state.prepareForVoice(config, nrpn_);
    return state;
  }

  SF2::Render::Voice::State::State makeState(int key, int velocity) const {
    auto found = state()->preset_.find(key, velocity);
    return makeState(found[0]);
  }

  SF2::MIDI::ChannelState& channelState() { return channelState_; }

  static void SamplesEqual(SF2::Float a, SF2::Float b) {
    XCTAssertEqualWithAccuracy(a, b, PresetTestContextBase::epsilon);
  }

private:

  struct State {
    SF2::IO::File file_;
    SF2::Render::InstrumentCollection instruments_;
    SF2::Render::Preset preset_;
    State(const char* path, size_t presetIndex)
    : file_{path}, instruments_{file_}, preset_{file_, instruments_, file_.presets()[presetIndex]} {}
  };

  State* state() const {
    if (!state_) state_.reset(new State(url().path.UTF8String, presetIndex_));
    return state_.get();
  }

  SF2::MIDI::ChannelState channelState_{};
  SF2::MIDI::NRPN nrpn_{channelState_};
  SF2::Float sampleRate_;
  size_t presetIndex_;
  mutable std::unique_ptr<State> state_;
};

struct SampleBasedContexts {
  PresetTestContext<0> context0;
  PresetTestContext<1> context1;
  PresetTestContext<2> context2;
};
