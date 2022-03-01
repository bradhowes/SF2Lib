#  DSP Namespace

Collection of common routines used for digital signal processing. Many of these are specific to working with MIDI and 
SF2 concepts. There are several lookup tables that convert from a MIDI value in the range [0-127] to a floating-point 
value. These are generated at compile-time for fast loading at runtime.

# Generated Tables

There are some lookup tables that are generated at compile time in order to speed up startup time. These tables are 
defined in `DSP/DSPTables.hpp` and `MIDI/ValueTransformer.hpp`. There is a script called `regen.sh` available in the
root directory that will rebuild the `DSPGenerated.cpp` contents.
