// Copyright © 2026 Brad Howes. All rights reserved.
//
// libFuzzer target for SF2 file parsing and the render-side code that consumes parsed entities. Build and run with
// `make fuzz` (needs Homebrew LLVM, since Apple clang ships without the libFuzzer runtime). See Fuzz/README.md.

#include <fcntl.h>
#include <unistd.h>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <string>

#include "SF2File/IO/File.hpp"
#include "SF2Lib/MIDI/ChannelState.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"
#include "SF2Lib/Render/Voice/Voice.hpp"

using namespace SF2;

namespace {

/// File descriptor of a scratch file that holds the current input. `File::load` needs a real descriptor.
int scratchFD()
{
  static int fd = [] {
    char path[] = "/tmp/sf2fuzz-XXXXXX";
    int value = ::mkstemp(path);
    if (value == -1) ::abort();
    ::unlink(path);
    return value;
  }();
  return fd;
}

/**
 Exercise everything that a host would do with a file that loads: build the presets, load each preset's samples, and
 configure, start and render a voice for every zone that matches a few key/velocity pairs. Work is capped so that a
 single input stays fast.
 */
void exercise(IO::File& file)
{
  Render::PresetCollection presets;
  presets.build(file);
  MIDI::ChannelState channelState;
  Render::Voice::Voice voice;
  voice.initialize(0, 48'000.0, Render::Voice::Sample::Interpolator::cubic4thOrder);

  auto presetCount = std::min(presets.size(), size_t(4));
  for (size_t presetIndex = 0; presetIndex < presetCount; ++presetIndex) {
    auto& preset = presets[presetIndex];
    if (!preset.loadSamples(file)) continue;
    size_t voices = 0;
    for (int key : {0, 60, 127}) {
      for (int velocity : {1, 127}) {
        for (const auto& config : preset.find(key, velocity)) {
          if (++voices > 16) break;
          voice.configure(config, channelState);
          voice.start();
          for (int sample = 0; sample < 256; ++sample) (void)voice.renderSample();
          voice.releaseKey({0, {}});
          for (int sample = 0; sample < 64; ++sample) (void)voice.renderSample();
          voice.stop();
        }
      }
    }
    preset.clearSamples();
  }
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size)
{
  int fd = scratchFD();
  if (::ftruncate(fd, 0) != 0 || ::pwrite(fd, data, size, 0) != ssize_t(size)) ::abort();

  IO::File file;
  if (file.load(fd) == IO::File::LoadResponse::ok) {
    exercise(file);
  }
  return 0;
}
