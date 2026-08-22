[![CI][status]][ci]
[![COV][cov]][ci]
[![][spiv]][spi]
[![][spip]][spi]
[![][cf1]][cf2]
[![][mit]][license]

# SF2Lib - a SoundFont (SF2) synthesizer in C++

This library can read SF2 SoundFont files and render audio samples from them in real-time. It properly reads in a
compliant SF2 file and can be used to obtain meta data such as preset names. It also has an audio rendering engine that
can generate audio samples for key events that come from (say) a MIDI keyboard. This library is currently being used by
my [SoundFonts][sf] and [SoundFontsPlus][sfp] applications for SF2 file parsing and, in the latter app, as the sample
generating engine.

Although most of the library code is generic C++17/23, there are a few bits that expect an Apple platform that has
the AudioToolbox and Accelerate frameworks available. The goal is to be a simple library for reading SF2 files as well
as a competent SF2 audio renderer whose output can be fed to any sort of audio processing chain, but it would probably
take some effort to remove it from the Apple ecosystem.

Note that this package depends on some general DSP headers and audio classes from my [DSPHeaders][dsp] package which is
also used by my various AUv3 extensions.

# SF2 Spec Support

Currently, all SF2 generators and modulators are supported and/or implemented according to the [SoundFont Spec
v2][spec]. However, this library does not currently contain chorus or reverb effects. When rendering, the library will
properly route a percentage of the signal to a chorus and reverb bus/channel if it is provided using the generator
settiings that configure the percentage.

The render [Engine][engine] `renderInto` method takes a [Mixer][mixer] instance which supports a main _dry_ bus and two
additional busses for the _chorus effect send_ and the _reverb effect send_. These are populated with samples from
active voices, and their levels are controlled by the `chorusEffectSend` and `reverbEffectSend` parameters mentioned
above. One can then connect bus 1 to a chorus effect and bus 2 to a reverb, and then connect those outputs and bus 0 of
this library to a mixer to generate the final output.

# Code

Here is a rough description of the top-level folders in SF2Lib:

* [Engine](Sources/Engine) -- a collection of C++ wrappers that use Swift/C++ bridging annotations to allow for
easy importing into Swift code of elements from the SF2File and SF2Lib packages.
* [SF2File](Sources/SF2File) -- collection of classes that provides for loading an SF2 file according to the container
definitions found in the SF2 v2 specification.
* [SF2Lib](Sources/SF2Lib) -- collection of classes used for sample rendering and MIDI processing.
* [SF2Util](Sources/SF2Util) -- various utility classes and functions used by the other libraries.
* [TestUtils](Sources/TestUtils) -- various utility classes and functions used by the unit tests.

# Unit Tests

There are quite a large number of unit tests that cover a good chunk of the code base. There are even some rendering
tests that will play audio at the end if configured to do so. This option is found in the
[Package.swift](Package.swift#L12) file, in the line `let playAudioDuringTests = false`. Change the `false` to `true` to
enable the audio output for *all* tests. This will increase the test run time, but it can be helpful when making code changes.

Alternatively, the unit tests with rendering capability have a `playAudio` attribute which can be set to `true` to play
the rendered output from a test. Note that the test results do not depend on this setting, but again enabling it does
increase the time it takes to run the tests due to the time it takes to play back the recorded audio samples.

# Performance

The current code has not been optimized for speed, but it still performs very well on modern devices, including mobile.
There are two tests (currently) that provide performance metrics:

* testEngineRenderPerformanceUsingCubic4thOrderInterpolation
* testEngineRenderPerformanceUsingLinearInterpolation

As their name suggests, these exercise a specific interpolation method. They both generate 1 second of audio at a 48K
sample rate, rendering 96 simultaneous notes. On an optimized build, the more expensive cubic 4th-order interpolation
tests take ~0.27s to complete, or ~1/4 of the time budget. The faster linear interpolation is down to ~0.25s.

Additional performance gains could be had by following the approach of [FluidSynth][fluid] and render 64 samples at a
time with no changes to most of the modulators and generators. Furthermore, one could check the pending MIDI event list
to see if it is empty, and choose a path that supports vectorized rendering.

# Swift Integration

All of the code in this package is C++/Objective C++ but the Swift package now depends on Swift v6.0 or later in order
to obtain access to the Swift C++ bridging that is now available. The bridging code is only found in the
[Engine](Sources/Engine) library component. It defines three bridging wrappers:

* [SF2Engine](Sources/Engine/include/SF2Engine.hpp) -- provides a way to create a new `SF2::Render::Engine` instance and
safely pass around in the Swift environment.
* [SF2FileInfo](Sources/Engine/include/SF2FileInfo.hpp) -- wrapper the reveals meta data of an SF2 file, and an
interator for the presets it defines.
* [SF2PresetInfo](Sources/Engine/include/SF2PresetInfo.hpp) -- wrapper for the meta data of a preset in an SF2 file.

Note that the most of the rendering and SF2 containers are not exposed by the Swift bridge, as they are not pertinent
when using the library for rendering in an AUv3 context.

# Credits

All of the code has been written by myself over the course of several years, but I have benefitted from the existence of
other projects, especially [FluidSynth][fluid] and their wealth of knowledge in all things SF2. In particular, if there
is any confusion about what the SF2 spec means, I rely on their interpretation in code. That said, any
misrepresentations of SF2 functionality are of my own doing.

[ci]: https://github.com/bradhowes/SF2Lib/actions/workflows/CI.yml
[status]: https://github.com/bradhowes/SF2Lib/workflows/CI/badge.svg
[cov]: https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/bradhowes/dbe62f18182c82eb36dc1030819bc54b/raw/SF2Lib-coverage.json
[spi]: https://swiftpackageindex.com/bradhowes/SF2Lib
[spiv]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbradhowes%2FSF2Lib%2Fbadge%3Ftype%3Dswift-versions
[spip]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbradhowes%2FSF2Lib%2Fbadge%3Ftype%3Dplatforms
[mit]: https://img.shields.io/badge/License-MIT-A31F34.svg
[license]: https://opensource.org/licenses/MIT
[dsp]: https://github.com/bradhowes/DSPHeaders
[fluid]: https://www.fluidsynth.org
[sf]: https://github.com/bradhowes/SoundFonts
[sfp]: https://github.com/bradhowes/SoundFontsPlus
[spec]: SoundFont%20Spec%202.01.pdf
[engine]: Sources/SF2Lib/include/SF2Lib/Render/Engine/Engine.hpp
[mixer]: Sources/SF2Lib/include/SF2Lib/Render/Engine/Mixer.hpp
[cf1]: https://www.codefactor.io/repository/github/bradhowes/sf2lib/badge
[cf2]: https://www.codefactor.io/repository/github/bradhowes/sf2lib
