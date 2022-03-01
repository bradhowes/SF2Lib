# SF2Lib -- an SF2 library in C++

This library can read SF2 files and render audio samples from them. It properly reads in a compliant SF2 file and can
be used to obtain meta data such as preset names. It also has an audio rendering engine that can generate audio samples
for key events that come from (say) a MIDI keyboard. Work on the rendering side is still on-going, but at present it
can generate audio at the right pitch.

Although nearly all of the code is generic C++17, there are bits that expect an Apple platform that has 
the AudioToolbox and Accelerate frameworks available. However, this usage is fairly isolated. The goal is to be a 
simple for reading SF2 files as well as a competent SF2 audio renderer whose output can be fed to any sort of audio
processing chain, not just macOS and iOS systems Core Audio systems.

# DSPTableGenerator

The SF2Lib relies on some lookup tables for fast value conversions of expensive operations at the cost of resolution.
The library comes with generated values, but it also has a command-line tool to regenerate it. In the Xcode project that
originally hosted this code, the generation of the table values was automated. Swift Package Manager does not support
this type of operation, so we are left with a manual step.

