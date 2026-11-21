# SF2Lib Code Review — November 2026

> Working copy for agents and contributors. File:line references are against commit `d921774` and drift as fixes land. When you finish a step from §10, add an entry to §11 (Progress log).

Scope: full read of `Sources/` (SF2File, SF2Lib, SF2Util, Engine) at commit `d921774`, checked against the SoundFont 2.01 spec PDF in the repo. Tests were read but **not run**: the review machine is Linux, and the targets need AudioToolbox, Accelerate and AVFoundation.

Severity scale: **Critical** = wrong audio in normal use, or a crash or memory corruption. **High** = spec violation, or a bug a user will hit in normal use. **Medium** = robustness or a latent bug. **Low** = style or cleanup.

---

## 1. Top 10 to fix first

| # | Severity | Issue | Where |
|---|---|---|---|
| 1 | Critical | Pitch bend saturates: incoming 14-bit value (0–16383, centre 8192) is clamped to 0–8191, so centre = full bend **up** | `ChannelState.hpp:22,70`, `Engine.mm:354` |
| 2 | Critical | Volume-envelope sustain level is computed in amplitude but read as dB-normalised — 12 dB sustain plays at ≈ −72 dB | `Envelope/Generator.mm:125` vs `Voice.hpp:184` |
| 3 | Critical | Low-pass filter is a no-op (`return sample;` is the first statement) | `LowPassFilter.hpp:27` |
| 4 | Critical | Any malformed chunk → `std::terminate` (exceptions thrown inside `noexcept` code paths) | `ChunkItems.hpp:48,112`, entity ctors, `Chunk::extract` |
| 5 | Critical | Unknown generator / modulator-destination IDs from a file index past the end of fixed arrays (memory corruption) | `State.mm:53-75,110`, `Definition.hpp:92` |
| 6 | High | Releasing the sustain pedal releases **every** voice, including keys still held down | `Engine.mm:180`, `Voice.mm:70-82` |
| 7 | High | `startAddrsOffset` / `startAddrsCoarseOffset` (gens 0 and 4) are ignored: `Index::start()` resets to 0, and `Bounds::startPos()` is never used | `Sample/Index.hpp:32` |
| 8 | High | Preset-level modulators (PMOD) are dropped entirely | `State.mm:68` |
| 9 | High | Real-time thread does file I/O, heap allocation/free and Obj-C messaging (program change, note-on, voice start/stop) | see §4 |
| 10 | High | Bookmark load: the `NSFileHandle` (and its fd) is closed when the block exits, yet `File` keeps using that fd for lazy sample loading | `Engine.mm:638` |

---

## 2. Architecture and data flow (as understood)

```
SF2 file ─► IO::File (RIFF walk, Pos/Chunk/ChunkItems<Entity::*>)        [SF2File]
              │  raw entity vectors + sorted preset index
              ▼
Render::PresetCollection ─► Render::Preset ─► Zone::Preset ─► Render::Instrument ─► Zone::Instrument
              │  (lazily) Preset::loadSamples → SampleVector<double> + NormalizedSampleSpan per zone
              ▼
Engine (AUv3 EventProcessor) ── MIDI/params ─► ChannelState, LiveGeneratorParameters
   noteOn → Preset::find(key,vel) → vector<Config> → Voice::configure/start
   render → for each active voice: Voice::renderInto(Mixer) → per-sample:
            LFOs/envelopes → Pitch::samplePhaseIncrement → Sample::Generator (interp) → gain → (filter) → pan → 3 busses
PresetsState: atomic pointer swap for file/preset changes; old state deleted lazily on next noteOn.
```

The layering is clean. SF2File knows nothing about rendering, the entity classes mirror the spec structs, and `GenValue` (value + adjustment + mods, cached) is a nice way to implement the 9.4 generator model. The weak spots are the boundary with untrusted file data (§5) and thread ownership in the Engine (§4).

---

## 3. Correctness bugs

### 3.1 Critical

**Pitch bend range.** `Engine::doMIDIEvent` builds `bend = (msb<<7)|lsb` (0–16383, centre 0x2000 = 8192). `ChannelState::setPitchWheelValue` clamps to `maxPitchWheelValue = 8191`, and `ValueTransformer` builds its pitch-wheel table for 0–8191 (`ControllerRange::_8192`). Result: any value ≥ 8191 is treated as full bend up, so a controller sending "centre" detunes everything by +2 semitones. `reset()` hides this by using 4096 as the rest value. Fix: use a 0–16383 domain (table size 16384, centre 8192), or subtract 8192 and use a signed domain, and add an end-to-end test that sends `E0 00 40` and checks for zero detune.

**Volume-envelope sustain domain mismatch.** `configureVolumeEnvelope` sets `sustainLevel_ = centibelsToAttenuationInterpolated(sustainCB)` (amplitude, e.g. 120 cB → 0.251). `Voice::renderSample` treats the envelope value as dB-normalised: `volEnvCB = 960 * (1 - env)` → 960 × 0.749 ≈ 719 cB ≈ −72 dB instead of −12 dB. `EnvelopeTests` asserts the 0.251 value, so the tests encode the bug. Fix: keep the envelope in normalised-dB space (`sustain = 1 - clamp(sustainCB, 0, 960)/960`), or keep it in amplitude and convert once with no second dB mapping. Add one integration test that checks the voice gain at sustain.

**Filter disabled.** `LowPassFilter::transform` returns before filtering. That makes initialFilterFc/Q (gens 8, 9), the default velocity→Fc modulator (8.4.2), and modLfoToFilterFc/modEnvToFilterFc (gens 10, 11; also commented out in `Voice.hpp:189-193`) all non-functional. The `ENABLE_LOWPASS_FILTER` flag in `Package.swift` is no longer referenced anywhere. The README's "all generators supported" claim is therefore not true today.

**`noexcept` + `throw` = terminate.** `Pos::readInto` / `makeChunk*` throw `File::LoadResponse`. They are called from `noexcept` functions: `ChunkItems::load`, every `Entity::*(Pos&)` constructor, `Version::load`, `Chunk::extract` and `Preset::loadSamples`. An exception that leaves a `noexcept` function calls `std::terminate`, so the `try/catch` in `File::load(int)` never sees it. A truncated `pdta` sub-chunk crashes the host instead of returning `invalidFormat`. Fix: remove `noexcept` from the parse path (or switch it to `std::expected`), and fuzz `File::load` (libFuzzer works well here).

**Out-of-bounds generator/modulator indices.** The spec says unknown generator and modulator values must be ignored (7.4, 7.5, 8.1). The code doesn't check them:
- `Generator::value()` → `Definition::definition(Index(raw))`. For raw ≥ 59 this reads past `definitions_`, and `State::setValue` then writes past `gens_`.
- `State::updateStateMods` does `gens_[mod.destination()]` with the raw `sfModDestOper`. A destination ≥ 59, or one with bit 15 set (2.04 link), writes outside the array.
- `Source::isValid()` accepts general index 127, but `Modulator::makeValueProvider`'s switch has no case for 127 and no return after the switch, which is UB. The amount source is never validated, so any invalid amount source reaches the same fall-through.
Fix: validate generator opers once at load and drop invalid entries. Validate the destination, the source and the amount source in `State::addModulator`, and give `makeValueProvider` a `default:` case.

### 3.2 High

**Sustain/sostenuto handling.**
- `applyPedals_RT` calls `releaseKey` on every active voice. With the pedal now up, `releaseKey` releases unconditionally, including voices whose key is still physically held. Tap the pedal while holding a chord and the chord cuts out.
- `postponedRelease_` is set but never read. That is the flag `applyPedals` should check (only release voices with `postponedRelease_ && !keyHeld`).
- `sostenutoActive_` and `postponedRelease_` are never reset in `configure`/`start`, so a recycled voice inherits sostenuto from its previous note.
- `ReleaseKeyState::minimumNoteDurationSamples` is passed in but ignored.

**Sample start offsets ignored.** `Bounds::make` computes `startPos_` correctly, but `Index::start()` sets `whole_ = 0`, and `startPos()` has no callers. `BoundsTests` exercises `Bounds` only. Fix: `whole_ = bounds_.startPos();`.

**PMOD ignored.** `State::configureWith(const Zone::Preset&)` applies generators only. Spec 7.4 and 9.5.1 say preset modulators add to identical instrument modulators, or add their own effect otherwise.

**Bookmark fd lifetime.** In `beginLoadBookmarkAndPreset_RT`, `concludeLoad_RT(fileHandle.fileDescriptor, …)` stores the fd in `File`/`Pos`. When the accessor block exits, ARC releases the `NSFileHandle` and closes the fd, and `stopAccessingSecurityScopedResource` follows. The next program change calls `Preset::loadSamples` on a closed fd, or worse a reused one (it could now point at a different file). Today that ends in terminate via `noexcept`. Fix: `dup()` the fd and give `File` ownership (it already has a `fd_` + destructor that are never used). Alternatively, load all samples eagerly while access is open.

**fd leak.** `File::load()` opens with `::open` but never assigns `fd_`, so the descriptor leaks once per file load. `Parser::parse` also never closes its fd. `File(File&&) = default` would double-close if `fd_` were ever set. Use a small RAII `UniqueFd`.

**Possible use-after-free on file switch (verify).** With the public `loadFileAndPreset(path)` API, voices are not stopped (only the SysEx path calls `allOff_RT`). After the load, `doRendering` resumes the old voices. Their `NormalizedSampleSpan`s point into the old `PresetsState`'s `SampleVector`, and the next `noteOn_RT` runs `ptr->deletePast()` while those voices may still be in their release tail. Separately, `deletePast` deletes only one level, so two loads before a note-on leak the older state, and `Engine` has no destructor, so the final state leaks too.

**`changeProgram_RT` can hang note-on forever.** It increments `presetChangesPending_` before checking `ptr`. If `ptr` is null, the counter is never decremented and `noteOn_RT` is gated off for good. Separately, `concludeUsePresetWithIndex_RT` (line 100) dereferences `ptr` after the `if (ptr)` guard.

**SysEx parsing trusts the payload.**
- `data[1]` and `data[2]` are read before any length check.
- `overrideCount` (a raw `size_t` from the wire) is never bounded against `length`, and `pathCount = … - 1` can underflow. Both lead to out-of-bounds reads from any MIDI source.
- The overrides are copied into a vector and then **never used**: the generator-override feature is unimplemented.
- The payload carries raw 8-bit `size_t` fields. MIDI SysEx data bytes must be < 0x80, and a 0xF7 byte inside `presetIndex` terminates the message. Encode every field 7-bit (Base64 already does this for the path).
- Manufacturer 0x7E is Universal Non-Real-Time. 0x7D is the ID reserved for non-commercial use.
- `[data initWithBase64EncodedData:data …]` sends `init` to an already-initialised object (UB). Use `[[NSData alloc] initWithBase64EncodedData:…]`.

**Voice-count limit not enforced.** The constructor initialises only `voiceCountLimit` voices, but `OldestVoiceCollection` hands out all `maxVoiceCount` (128) indices. Voices beyond the limit get used with an uninitialised `voiceIndex_` and the default interpolator. `assert(voiceCountLimit <= 128)` disappears in release builds, so `SF2Engine::create(…, 200)` writes past `voices_`.

**Live attenuation changes ignored for sounding notes.** `initialAttenuation_` is captured once in `Voice::start()`, so CC7, CC11 and AU-parameter changes never affect held notes. That breaks volume and expression swells. Read `state_.modulated(initialAttenuation)` in the render path (once per block is enough).

**`Instrument`/`Preset` zone links are unchecked.** `&sampleHeaders[resourceLink()]` and `&instruments[resourceLink()]` have no bounds check (`checkedVectorIndexing` is off by default). The spec says a value ≥ the terminal record means "reject file" (7.5, 7.9).

### 3.3 Medium

- **Loop wrap at high pitch:** `Index::increment` subtracts `loopSize()` once. With a short loop (≥ 32 samples per spec) and a large increment, `whole_` can stay past `endLoopPos` and step outside the span. Use `while`, or a modulo.
- **Interpolation at loop end:** `sample()` only wraps `whole == endLoopPos`. Cubic interpolation also reads `whole+2`, which can be `endLoopPos+1`. `before()` wraps on the *first* pass through `startLoopPos`, before any looping has happened.
- **Pitch quantised to 1 cent:** `power2Lookup(int(round(phase)))`. Each sample-rate term is also rounded separately (`sampleRateDeltaCents`). Detuned layers beat at the wrong rate and vibrato stair-steps. Interpolate the table, or use `exp2` once per block.
- **Release time capped at 5000 timecents (≈18 s)** in `releaseTimecentsToSeconds`. The spec and `Definition` both allow 8000 (≈100 s).
- **exclusiveClass:** `Config` reads it only from the local instrument zone (the global zone is ignored, which disagrees with `Voice::exclusiveClass()`). Voices are also hard-stopped; a ~5 ms fast release would avoid clicks.
- **Duplicate bank/program:** spec 7.2 says the *first* preset in PHDR wins. `std::sort` is not stable; use `std::stable_sort`.
- **Empty or missing chunks:** `ChunkItems::size()` is `items_.size() - 1`, which underflows for an empty or missing chunk. A file without `phdr` then makes `presetIndicesOrderedByBankProgram_.resize(SIZE_MAX)` (terminate). `end()` is `items_.end() - 1` on an empty vector, which is UB. `makeChunkList` computes `buffer[1] - 4` without checking ≥ 4.
- **Non-terminated names:** `trim_property(char[N])` can leave all 20 bytes non-zero. `Preset::name()` then reads past the array. Copy at most `N-1` bytes.
- **`std::isspace` / `std::isprint` on plain `char`:** UB for bytes ≥ 0x80 (Latin-1 names are common). Cast to `unsigned char`. Same for `decoder[int(c)]` in Base64.
- **`loadSamples` for a preset with no sample zones:** `maxEnd - minStart` underflows and `resize` throws inside `noexcept`. Also, `sampleDataBegin_` carries the *file* end, not the `smpl` chunk end, so headers that point past `smpl` read `pdta` bytes as audio.
- **No file-level validation:** `ifil` major version, presence of the required chunks, terminal records, `size % entity_size == 0` (spec: "reject"), and `sdta`/`pdta` ordering.
- **`Voice(Voice&&) = default`:** `Pitch` holds `const State& state_` to the *moved-from* voice. This is safe today only because `voices_` is a `std::array`. Delete the move constructor or rebind.
- **Render block capture:** `SF2Engine::getRenderBlock` captures the raw `Engine*`. Capture the `shared_ptr` (`auto engine = impl_;`); Obj-C++ blocks copy C++ captures.
- **`Pos::operator bool` returns true when *invalid*.** That's surprising; rename to `isValid()` / `atEnd()`.
- **`secondsToCents` is wrong:** `log2(v * 1200)` should be `1200 * log2(v)`. It has no callers yet. Doc comments in `DSP.hpp` are off too ("20 cB → 0.1", "400 = 0.001"; `clampFilterCutoff` says 13500 but clamps to 20000).
- **NRPN decoding:** an unrelated CC (e.g. CC1) between select and data entry cancels decoding. Data-entry LSB arriving after MSB is ignored. RPN 0 (pitch-bend range) is not decoded at all, so pitch-wheel sensitivity can't be changed over MIDI.

---

## 4. Real-time safety

The header says the design goal is no allocation on the render thread. These paths break that:

| Path (render thread) | Problem |
|---|---|
| `changeProgram_RT` → `concludeUsePresetWithIndex_RT` → `PresetsState::changeActivePreset` → `Preset::loadSamples` | **Disk reads** + `vector::resize` of possibly tens of MB |
| `concludeUsePresetWithIndex_RT` | `NSString stringWithCString`, `AUParameter setValue` (KVO/observers) |
| `startVoice_RT` / `stopVoice_RT` → `updateActiveVoiceCount_RT` | `[parameterTree_ parameterWithAddress:]` + `setValue:` for every voice start/stop |
| `noteOn_RT` → `Preset::find` / `Collection::filter` | Two `std::vector` allocations per note-on |
| `noteOn_RT` → `PresetsState::deletePast` | `delete` of a whole File + PresetCollection + sample buffers |
| SysEx handlers | `std::vector`, Base64 `std::string`, `dispatch_async` block copy, `NSData` |
| `Zone::Preset::instrument()`, `Zone::Instrument::samples()` | Can `throw std::runtime_error` |
| Per-event `os_log_info` (doMIDIEvent, startVoice, LiveGeneratorParameters…) | Mostly cheap, but noisy; prefer signposts/debug level |

Suggested shape: make `Preset::find` fill a fixed-capacity `std::array`/`static_vector` owned by the Engine. Defer program-change sample loading to `workQueue_`, as the SysEx file path already does, and let the RT thread only flip the atomic index. Post old `PresetsState` objects to a lock-free "graveyard" freed on the work queue once no voice references them (a generation counter per voice works). Publish voice-count and load-finished values through atomics that a main-thread timer pushes into the `AUParameterTree`.

Naming: `_RT` is used for functions that actually run on the work queue (`beginLoad…_RT`, `concludeLoad_RT`). Something like `_RT` / `_WQ` / `_Any` would make the threading contract readable.

---

## 5. SoundFont 2.01 conformance checklist

| Spec item | Status |
|---|---|
| 7.x RIFF structure, chunk tags, entity sizes (38/4/10/4/22/46) | ✅ |
| 7.x "reject if size not multiple of N / index ≥ terminal" | ❌ not validated |
| 7.2 duplicate bank/program → first wins | ⚠️ unstable sort |
| 7.3/7.7 global zone rules (first zone only; empty zone ignored; non-global without terminal gen ignored) | ✅ |
| 7.4/7.5 duplicate gen/mod in zone → last wins | ✅ (replace semantics) |
| 7.10 originalPitch 128–254/255 → 60 | ✅ (255 also forces constant pitch — beyond spec, worth documenting) |
| 8.1 unknown generators ignored | ❌ OOB (see §3.1) |
| 8.1.2 ranges / defaults table | ✅ `Definition.mm` matches the spec table |
| Gen 0/4 start offsets | ❌ ignored |
| Gen 1/2/3/12/45/50 end/loop offsets | ✅ via `Bounds` |
| Gen 8/9/10/11 filter | ❌ filter disabled; 10/11 not wired |
| Gen 38 releaseVolEnv/30 releaseModEnv max 8000 | ⚠️ capped at 5000 |
| Gen 34 attackVolEnv "convex, linear in amplitude" | ⚠️ implemented linear in dB (acknowledged in comments) |
| Gen 37 sustainVolEnv | ❌ domain mismatch |
| Gen 46/47 keynum/velocity overrides | ✅ |
| Gen 57 exclusiveClass | ⚠️ global zone ignored; hard cut |
| 8.2.1 "No Controller" source = value 1, not a way to turn a modulator off | ❌ returns 0 (`Modulator.mm:95`) |
| 8.2.1 reserved source indices → ignore modulator | ⚠️ 127 accepted; amount source unchecked |
| 8.4 default modulators | ✅, with two deviations worth documenting: CC10→pan amount 500 (spec says 1000; FluidSynth makes the same choice), and velocity→Fc has no 0x502 amount source (matches 2.04, not 2.01) |
| 8.5 preset-level-forbidden generators ignored | ✅ (`isAvailableInPreset`) |
| 9.4 generator precedence (default → global inst → local inst; preset adds) | ✅ |
| 9.5.1 modulator identity includes transform | ⚠️ `operator==` ignores transform (comment cites 7.4 only) |
| 9.5.1 PMOD additive | ❌ ignored |
| 9.5.1 inst modulators supersede defaults | ✅ |
| 7.10 stereo links "played synchronously, pitch from right sample" | ❌ not implemented (acknowledged in `Voice.hpp`) |
| Modulated value clamping to gen range after summation | ⚠️ ad hoc per consumer (envelopes, filter, pan are clamped; tuning, Q, send levels partially) |

---

## 6. Optimisation opportunities

1. **Memory:** samples are stored as `double` (`Float = double`), 4× the size of the int16 source. GeneralUser GS (~30 MB) becomes ~120 MB per fully loaded preset range. Storing `float` (or keeping `int16` and scaling at interpolation) halves or quarters that and improves cache behaviour. The render math could be `float` as well; the AU output is `float` anyway.
2. **Block-rate control:** pan, sends, initialAttenuation, filter coefficients and the phase-increment components only change on MIDI or parameter events. Compute them once per render slice; EventProcessor already splits at event boundaries. Per-sample, keep only the LFO/envelope ramps. That also opens the FluidSynth-style 64-sample inner loop the README mentions, and SIMD.
3. **Interpolator dispatch:** a member-function pointer is called per sample. Template `Voice::renderInto` on the interpolator and branch once per block.
4. **Silent tail:** `Voice::renderInto` loops over the remaining frames calling `mixer.add(…, 0, 0, …)`. That's pure overhead; just stop.
5. **`updateStateMods`:** iterates all 60 generators plus every modulator for every voice on every CC, including CCs no modulator listens to. Precompute a per-voice bitmask of the CCs/sources it depends on.
6. **`setContinuousControllerValue` always returns true**, so every CC notifies all voices even when the value didn't change.
7. **`loadSamples`** loads the whole `[minStart, maxEnd]` range for a preset. For drum kits whose samples are scattered across the bank, that is most of the file. Per-sample-header spans (with a de-dupe map) would cut memory a lot.
8. **`Preset::find`** walks preset zones linearly, then instrument zones. That's fine for typical counts; a 128-entry key→zone-list table built at load would make note-on O(matches).
9. **Time-budget check:** `Timer::delta` is called once per voice. Fine, but `voice.stop()` on budget overrun is an abrupt cut; a fast release, or skipping the voice for one cycle, is gentler.

---

## 7. Style and idioms

- `noexcept` is applied mechanically, including on functions that throw or call throwing code. Reserve it for code that really can't fail (move ops, RT render path).
- Exceptions used as control flow (`throw File::LoadResponse::invalidFormat`, an enum value). Prefer `std::expected<T, LoadResponse>` (C++23 is already enabled).
- `(this + 1)->firstZoneIndex()` in `Preset`/`Bag`/`Instrument` relies on the entity living inside a vector with a sentinel. That is fragile, and UB for a stand-alone copy. Compute counts in `ChunkItems` instead.
- `using namespace DSPHeaders;` inside `namespace SF2` in a widely-included header (`Types.hpp`) leaks every DSPHeaders name into all SF2 code. `#import` is used inside a C++ header.
- `const` data members (`NormalizedSampleSpan::span_`, `Chunk::tag_`…) disable assignment for no real benefit; prefer private non-const members.
- Redundant `inline` on in-class definitions throughout; `inline static size_t entity_size` is non-const in `Modulator` (const elsewhere).
- Duplicate size checks in `Chunk` and `ChunkList` constructors; `NormalizedSampleSource` (SF2File) and `NormalizedSampleSpan` (SF2Lib) are near-duplicates. `SampleSourceCollection.mm` is empty and `build()` doesn't clear.
- `std::cout` in library code (`File::load` prints "loading: …", `SF2Engine::create`).
- Stale comments: `Parser.hpp` (FormatError, "size" parameter), `Version.hpp` says 'iver' but it parses `ifil`, `ChannelState::setPitchWheelSensitivity` says the default is 200 when it is 2, `Modulator.hpp` says a 'none' source returns 0.0 (contradicts 8.2.1).
- Advertised but unimplemented: mono mode, portamento, retrigger, minimum note duration, generator overrides, `durationBuckets_`, plus the `ENABLE_LOWPASS_FILTER` / `USE_ACCELERATE` flags. Either implement these or remove them from the AU parameter tree and `Package.swift`.
- MIDI channel nibble ignored (omni). Fine for an AUv3 instrument, but worth documenting.

---

## 8. Tests

The unit coverage of individual classes is good: Bounds, envelopes, LFO, modulator sources, transformer curves, OldestVoiceCollection. The gaps are the **integration seams**, which is where most of the bugs above live:

- MIDI bytes → `doMIDIEvent` → audible effect (pitch bend centre, CC7 on a held note, sustain pedal with a held key, program change).
- Envelope value → voice gain at sustain (would have caught §3.1).
- `startAddrsOffset` affecting the first rendered sample.
- PMOD-bearing preset.
- Malformed-file corpus: truncated chunks, missing `phdr`, out-of-range gen IDs, a 20-char name, bad indices. Plus a libFuzzer target on `File::load(fd)`.
- An ASan/UBSan scheme in CI. `-fsanitize=address,undefined` would flag several items in §3 straight away.

---

## 9. Repo hygiene

- `cmake/compile_commands.json` is tracked (with machine-specific absolute paths) even though `cmake/` is git-ignored.
- Emacs backup directories (`.~/`, `*.~`) are scattered under `Sources/`, `Tests/` and `.github/`; add them to `.gitignore`.
- `Tests/…/Voice/.~/VoiceTests.mm~` and the other backups contain stale code that shows up in greps (e.g. old `ENABLE_LOWPASS_FILTER` uses).

---

## 10. Suggested order of work

1. Pitch-bend domain and sustain-level domain: two small, contained fixes, each with an integration test.
2. Pedal logic (`postponedRelease_`, reset flags on voice start).
3. `Index::start()` → `bounds_.startPos()`.
4. Parse-path hardening: drop `noexcept`, validate gen/mod IDs and indices, fix `ChunkItems` empty handling. Add the fuzz target.
5. File-descriptor ownership (bookmark dup, RAII fd).
6. Re-enable and wire the filter (frequency = Fc + modLfo·Fc + modEnv·Fc), computed per block.
7. PMOD support; "No Controller" = 1; reject reserved sources.
8. RT-safety refactor (§4) and the PresetsState lifetime/graveyard.
9. Memory: switch sample storage to `float`.

---

## 11. Progress log

**Step 1 — done (2026-11-21). Committed as `4739ab2` "Fixed pitch bend and sustain levels."; tests fixed and passing per user.**
- Pitch bend: `ChannelState::maxPitchWheelValue` is now 16383 (rest = 8192). `Source::ControllerRange::_8192` → `_16384`. `ValueTransformer` builds its pitch-wheel tables from `maxPitchWheelValue`.
- Sustain: new `Envelope::volumeEnvelopeToCentibels` / `centibelsToVolumeEnvelope` in `Envelope/Generator.hpp` are the single definition of the normalised-dB mapping. They are used by `configureVolumeEnvelope` (sustain level) and `Voice::renderSample` (gain).
- Tests updated: `ChannelStateTests` (rest 8192, clamp range), `ModulatorTests::testPitchWheelToInitialPitch` (new full-up value 12599.243…), `EnvelopeTests::testVolumeEnvelopeSustainLevel` (normalised-dB expectations).
- Tests added: `EngineTests::testMIDIPitchBendDecodesFull14BitRange`, `testMIDIPitchBendCentreIsNeutral` (renders with/without `E0 00 40` and requires identical output), `testVolumeEnvelopeSustainLevelIsAppliedInDecibels` (sustain 120 cB → RMS ratio 0.2512 ± 2 %), and `EnvelopeTests::testVolumeEnvelopeSustainRoundTripsThroughVoiceGainMapping`.
- Expect golden-sample assertions in rendering tests (`EngineTests`, `VoiceTests`, etc.) to change wherever a preset has a non-zero `sustainVolEnv`. Those values encoded the old, wrong gain and need to be regenerated from the `dumpSamples` output.
