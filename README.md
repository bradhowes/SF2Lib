[![CI](https://github.com/bradhowes/SF2Lib/workflows/CI/badge.svg)](https://github.com/bradhowes/SF2Lib/actions/workflows/CI.yml)
[![COV](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/bradhowes/dbe62f18182c82eb36dc1030819bc54b/raw/SF2Lib-coverage.json)](https://github.com/bradhowes/SF2Lib/blob/main/.github/workflows/CI.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbradhowes%2FSF2Lib%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/bradhowes/SF2Lib)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fbradhowes%2FSF2Lib%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/bradhowes/SF2Lib)
[![License: MIT](https://img.shields.io/badge/License-MIT-A31F34.svg)](https://opensource.org/licenses/MIT)

# SF2Lib - a SoundFont (SF2) Library for Parsing and Rendering in C++ (mostly) for iOS, macOS, and tvOS

This library can read SF2 SoundFont files and render audio samples from them. It properly reads in a compliant SF2 file
and can be used to obtain meta data such as preset names. It also has an audio rendering engine that can generate audio
samples for key events that come from (say) a MIDI keyboard. Work on the rendering side is still on-going, but at
present it can generate audio at the right pitch. This library is currently being used by my
[SoundFonts](https://github.com/bradhowes/SoundFonts) application for SF2 file parsing, and now experimental rendering.

Although much of the code is generic C++17/23, there are bits that expect an Apple platform that has
the AudioToolbox and Accelerate frameworks available. As such, there are some code files that have the `.mm` suffix
so that they compile as Obj-C++ instead of C++ -- these "bridge" files provide a means to interact with the SF2Lib from
Swift code. However, such cases are fairly isolated. The goal is to be a simple library for reading SF2 files as well
as a competent SF2 audio renderer whose output can be fed to any sort of audio processing chain, not just macOS and iOS
Core Audio systems.

This package depends on some general DSP and audio classes from my
[AUv3Support](https://github.com/bradhowes/AUv3Support) package.

# SF2 Spec Support

Currently, all SF2 generators and modulators are supported and/or implemented according to the
[SoundFont Spec v2](SoundFont%20Spec%202.01.pdf).
However, this library does not currently contain chorus or reverb effects. When rendering, the library will properly
route a percentage of the signal to a chorus and reverb bus/channel if it is provided using the generator settiings
that configure the percentage.

The render [Engine](Sources/SF2Lib/include/SF2Lib/Render/Engine/Engine.hpp) `renderInto` method takes a
[Mixer](Sources/SF2Lib/include/SF2Lib/Utils/Mixer.hpp) instance which supports a main "dry" bus and two busses for the
"chorus effect send" and a "reverb effect send". These are populated with samples from active voices, and their levels
are controlled by the `chorusEffectSend` and `reverbEffectSend` parameters mentioned above. One can then connect bus 1
to a chorus effect and bus 2 to reverb, and then connect those outputs and bus 0 of this library to a mixer to generate
the final output.

# Code

Here is a rough description of the top-level folders in SF2Lib:

* [DSP](Sources/SF2Lib/DSP) -- various utility functions for signal processing and converting values from one unit to
another. Some of these conversions rely on tables generated at compile time using the C++ `constexpr` facility.
* [Entity](Sources/SF2Lib/Entity) -- representations of entities defined in the SF2 spec. Provides for fast loading of
SF2 files into read-only data structures.
* [include](Sources/SF2Lib/include/SF2Lib) -- headers for the library. The routines in the rendering path are mostly
inline for speed.
* [IO](Sources/SF2Lib/IO) -- performs the reading and loading of SF2 files.
* [MIDI](Sources/SF2Lib/MIDI) -- state for a MIDI connection.
* [Render](Sources/SF2Lib/Render) -- handles rendering of audio samples from SF2 entities. Usually the API
found in this namespace will be used in a real-time rendering thread. As such, there are no locks or memory allocations
that are performed in this code.
* [Resources](Sources/SF2Lib/Resources) -- contains a
[Configuration.plist](Sources/SF2Lib/Resources/Configuration.plist) file that sets some configuration options.

# Unit Tests

There are quite a lot (yet not enough) unit tests that cover nearly all of the code base. There are even some rendering
tests that will play audio at the end if configured to do so. This option is found in the
[Package.swift](Package.swift#L86) file, in the line `.define("PLAY_AUDIO", to: "0", .none)`. Change the "0" to "1" to
disable the audio output. Alternatively, the unit tests with rendering capability have a `playAudio` attribute which can
be set to `true` to play the rendered output from a test. Note that the test results do not depend on this setting, but
enabling it does increase the time it takes to run the tests due to the time it takes to play back the recorded audio
samples.

# Performance

The current code has not been optimized for speed, but it still performs very well on modern devices, including mobile.
There are two tests (currently) that provide performance metrics:

* testEngineRenderPerformanceUsingCubic4thOrderInterpolation
* testEngineRenderPerformanceUsingLinearInterpolation

As their name suggests, these exercise a specific interpolation method. They both generate 1 second of audio at a 48K
sample rate, rendering 96 simultaneous notes. On an optimized build, both tests take ~0.4s to complete.

Addional performance gains could be had by following the approach of FluidSynth and render 64 samples at a time with no
changes to most of the modulators and generators. Furthermore, one could check the pending MIDI event list to see if it
is empty, and choose a path that supports vectorized rendering.


# Credits

All of the code has been written by myself over the course of several years, but I have benefitted from the existence of
other projects, especially [FluidSynth](https://www.fluidsynth.org) and their wealth of knowledge in all things SF2.
In particular, if there is any confusion about what the SF2 spec means, I rely on their interpretation in code. That
said, any misrepresentations of SF2 functionality are of my own doing.
