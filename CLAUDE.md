# SF2Lib: notes for coding agents

SF2Lib is a SoundFont 2 (SF2) file parser and real-time synthesizer, written in C++23 / Objective-C++ (`.mm`) and shipped as a Swift package. Its main client is an AUv3 instrument, so the render path runs on a real-time audio thread.

## Current work plan

The plan lives in **`Docs/CodeReview.md`**. Work through §10 ("Suggested order of work") **one step at a time**:

1. Read the relevant findings in §3–§5 before changing any code.
2. Make the fix. Add or update tests that exercise the behaviour end to end, through `Engine::doMIDIEvent` / `TestEngineHarness` where that makes sense, not just at unit level.
3. Build and run the full test suite. All tests must pass.
4. Append an entry to §11 (Progress log): what changed, which tests were added, and anything left over.
5. Stop and summarise for the user. Don't start the next step without being asked.

Steps already done are listed in §11.

## Layout

| Path | Role |
|---|---|
| `Sources/SF2File` | RIFF/SF2 parsing (`IO::File`, `Pos`, `Chunk`, `ChunkItems<T>`) and the spec entity structs (`Entity::*`) |
| `Sources/SF2Lib` | Rendering: `Render::Engine::Engine`, `Voice`, `State`, envelopes, LFOs, filter, zones/presets; MIDI state in `MIDI/` |
| `Sources/SF2Util` | DSP lookup tables and conversions (`DSP.hpp`), string utils, Base64 |
| `Sources/Engine` | Swift/C++ bridging wrapper (`SF2Engine`) |
| `Sources/TestUtils` | Test harness (`TestEngineHarness`, sample contexts) and test `.sf2` resources |
| `Tests/SF2LibTests`, `Tests/EngineTests` | XCTest suites (Objective-C++) |
| `SoundFont Spec 2.01.pdf` | The reference spec. Cite section numbers (e.g. "8.1.2") in comments when implementing spec behaviour |

Dependency: [DSPHeaders](https://github.com/bradhowes/DSPHeaders) (Swift package). `useLocalDSPHeaders` in `Package.swift` must stay `false` in commits.

## Build and test

- In Xcode, use the `SF2Lib-Package` scheme with the `SF2Lib-Package.xctestplan` test plan.
- From the command line, `make test-macOS` (or `make` for both platforms plus coverage).
- Rendering tests compare against hard-coded sample values. If a deliberate audio change breaks them, regenerate the
  values from the test's `dumpSamples` output and say so in the commit message. Never loosen tolerances to make a test
  pass. Note that the output from `dumpSamples` contains the actual `XCTestAssertEqualWithAccuracy` statement to
  use with enough significant digits.

## Conventions

- Match the existing style: 2-space indent, 120-column lines, `/** ... */` doc comments with `@param` / `@returns`, `SF2::` namespaces mirroring directories.
- Functions suffixed `_RT` are intended for the render thread. Don't add allocation, locks, file I/O, Objective-C messaging or exceptions to render-thread paths.
- Don't put `noexcept` on code that can throw or that calls code that throws. Parser errors currently use `throw File::LoadResponse`.
- Untrusted input (SF2 files, MIDI/SysEx bytes) must be validated before it is used as an index.
- Keep changes focused on the current step. Note unrelated problems in the progress log rather than fixing them in passing.
- Don't commit build products, `cmake/` output, or editor backup files (`.~/`, `*~`).
