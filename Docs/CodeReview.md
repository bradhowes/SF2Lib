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
- ~~**exclusiveClass:** `Config` reads it only from the local instrument zone (the global zone is ignored, which disagrees with `Voice::exclusiveClass()`). Voices are also hard-stopped; a ~5 ms fast release would avoid clicks.~~ Fixed (see §11, gen 57 follow-up).
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

Re-evaluated on 2026-11-22 against `2357c6a` (after steps 1–9 in §10). Each row was checked against the current code. The step that changed a row is given in brackets.

| Spec item | Status |
|---|---|
| 7.x RIFF structure, chunk tags, entity sizes (38/4/10/4/22/46) | ✅ |
| 7.x "reject if size not multiple of N / index ≥ terminal" | ✅ [step 4] `ChunkItems::load` rejects bad sizes. `File::validate` checks terminal records, zone/gen/mod index order and range, and instrument/sample links. Linked samples must lie inside `smpl` |
| 5.1 ifil "missing, or its size is not four bytes → reject" | ✅ a wrong size is rejected [step 4], as is a *missing* `ifil` |
| 7.2 duplicate bank/program → first wins | ✅ duplicates appear in order seen in file
| 7.3/7.7 global zone rules (first zone only; empty zone ignored; non-global without terminal gen ignored) | ✅ (unknown generators are now dropped before a zone is classified [step 4]) |
| 7.4/7.5 duplicate gen/mod in zone → last wins | ✅ instrument level replaces; preset level skips all but the last of identical modulators in a zone [step 7] |
| 7.10 originalPitch 128–254/255 → 60 | ✅ (255 also forces constant pitch — beyond spec, worth documenting) |
| 7.10 sample rate 0 → "nearest practical value" | ✅ [step 4, found by fuzzing] clamped to 400 Hz in `Pitch::configure` |
| 5.4/5.5/7.10 ROM samples (no `irom`/`iver` → "accesses … should be terminated and not sound") | ✅ `File::validate` rejects the file if an instrument zone uses a ROM sample header (ROM headers no instrument uses are allowed). The spec only asks for such zones to be silent; with no ROM support at all, rejecting is stricter but simpler |
| 8.1 unknown generators ignored | ✅ [step 4] `Generator::isValid`; dropped in `Zone::Collection::add`, skipped in `State` |
| 8.1.2 ranges / defaults table | ✅ `Definition.mm` matches the spec table |
| Gen 0/4 start offsets | ✅ [step 3] `Index::start()` uses `Bounds::startPos()`; bounds are computed after live parameters are applied |
| Gen 1/2/3/12/45/50 end/loop offsets | ✅ via `Bounds` (now also settable through the AU parameter tree [step 3]) |
| Gen 54 sampleModes looping | ✅ loops only when `Bounds::hasLoop()` [steps 3, 4]. `Index::increment` wraps by modulo, so any increment stays inside the loop (§3.3 "loop wrap at high pitch"). Interpolation reads at or past the loop end map back into the loop, and the sample before the loop start is the loop end only once playback has wrapped (§3.3 "interpolation at loop end") |
| Gen 8/9/10/11 filter | ✅ [step 6] enabled; Fc = initialFilterFc + modLfo·gen10 + modEnv·gen11 (cents); 8.1.2 #8 bypass (≥ 20 kHz with Q = 0) and #9 DC gain −Q/2 implemented. Deviation: the gain at the cutoff is Q − 3.01 dB rather than Q (FluidSynth convention, so 0 cB is a non-resonant Butterworth) |
| Gen 38 releaseVolEnv/30 releaseModEnv max 8000 | ✅ `releaseTimecentsToSeconds` now clamps at 8000, matching `Definition.mm` |
| Gen 34 attackVolEnv "convex, linear in amplitude" | ✅ the volume envelope ramps its attack *progress* linearly and outputs `volumeEnvelopeAttackCurve(progress)`, the normalised-dB value whose gain equals the progress, so the attack is linear in amplitude (half way = −6 dB). A release during the attack starts from the shaped level. Deviation: the modulation envelope attack (gen 26, "linear in Hz") stays linear, as in FluidSynth, because the right curve depends on the destination and depth |
| Gen 37 sustainVolEnv | ✅ [step 1] sustain level and voice gain share one normalised-dB mapping |
| Gen 46/47 keynum/velocity overrides | ✅ |
| Gen 57 exclusiveClass | ✅ read from the global instrument zone, overridden by the local zone. Other sounding voices of the class, including ones already releasing, get a 5 ms release on both envelopes instead of a hard stop |
| 8.2.1 "No Controller" source = value 1, not a way to turn a modulator off | ✅ [step 7] |
| 8.2.1 reserved source indices → ignore modulator | ✅ [steps 4, 7] general 127 and other reserved indices rejected; CC 0, 6, 32–63, 98–101, 120–127 rejected; the amount source and the destination are validated too |
| 8.2.1 source 16 "pitch wheel sensitivity … sent from the MIDI RPN 0 command" | ✅ `ChannelState` decodes RPN 0 (CC 101/100 = 0/0, then Data Entry MSB = semitones) into `pitchWheelSensitivity`. An RPN stays selected across unrelated CCs until another RPN/NRPN or the RPN null (127/127). Data Entry LSB (cents), Data Entry increment/decrement and other RPNs are ignored |
| 8.2.4 / 7.4 unknown `sfModTransOper` values | ✅ a modulator with an unknown transform is ignored (7.4, 10.3). The 2.04 "absolute value" transform (2) is supported and applied to the multiplier output (9.5.1) |
| 8.4 default modulators | ✅, with two deviations worth documenting: CC10→pan amount 500 (spec says 1000; FluidSynth makes the same choice), and velocity→Fc has no 0x502 amount source (matches 2.04, not 2.01) |
| 8.5 preset-level-forbidden generators ignored | ✅ (`isAvailableInPreset`) |
| 9.4 generator precedence (default → global inst → local inst; preset adds) | ✅ |
| 9.5.1 modulator identity includes transform | ✅ `operator==` compares source, destination, amount source and transform (9.5.1) for superseding and summing. Duplicates within a zone use the three enumerators only (7.4, `hasSameEnumerators`) |
| 9.5.1 PMOD additive | ✅ [step 7] preset modulators add their amount to an identical instrument/default modulator, or are added as new; local preset supersedes global preset |
| 9.5.1 inst modulators supersede defaults | ✅ |
| 7.10 stereo links "played synchronously, pitch from right sample" | ❌ not implemented (acknowledged in `Voice.hpp`) |
| Modulated value clamping to gen range after summation | ✅ clamped where each value is used (10.5). `State::modulated` still returns the raw sum; consumers that did not already bound it use `State::modulatedInRange`, which clamps to the generator's `Definition` range: coarseTune, the three pitch depths, modLfoToVolume, the two filter Fc depths and the key-number envelope scaling. LFO delays use `DSP::lfoDelayTimecentsToSeconds` (−32768 = no delay). Envelope times, sustain levels, LFO frequencies, filter Fc/Q, attenuation, pan and the sends were already bounded by their conversions. fineTune is deliberately not clamped: it carries the pitch-wheel modulator |

**Summary:** of the 8 ❌ rows in the original review, 7 are now ✅ (size/index validation, unknown generators, start offsets, filter, sustain, "No Controller", PMOD); release-time capping (⚠️) and reserved sources (⚠️) are also ✅. Still ❌: stereo links. (RPN 0 / pitch-wheel sensitivity, listed in this re-evaluation, has since been fixed.) Open ⚠️ items, roughly in order of audible impact:
- duplicate presets;
- ROM samples;
- missing `ifil`.

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

**Step 2 — done (2026-11-21). Committed as `6ee5433` "Fix sustain/sostenuto pedal release logic."; `make test-macOS`: 267 tests, 0 failures.**
- `Voice` now tracks two separate things: `keyDown_` (the physical key, cleared by every note-off) and the new `released_` (the envelopes have entered release). `releaseKey` always clears `keyDown_`, and either sets `postponedRelease_` (when held by sustain, or by sostenuto with `sostenutoActive_`) or releases the envelopes. A repeated note-off on a voice that is already released no longer restarts its release stage.
- New `Voice::pedalReleased(PedalState)`: clears `sostenutoActive_` once sostenuto is up, then releases the voice only if `postponedRelease_` is set and no remaining pedal holds it. `Engine::applyPedals_RT` calls this instead of `releaseKey`, so lifting a pedal no longer cuts off held keys.
- `Voice::start()` resets `released_`, `postponedRelease_` and `sostenutoActive_`, so a recycled voice no longer inherits pedal state.
- `canLoop()` for `sampleModes` 3 (loop during key press) now uses `!released_`, so a note held by a pedal keeps looping as it did before.
- Applying sostenuto (`applySostenutoPedal_RT` → `isKeyDown()`) now captures only physically held keys. It used to also capture notes that were only being held by sustain.
- Tests updated: `VoiceTests::testSostenuto` and `testSustain` now drive pedal-up through `pedalReleased`, and check `isKeyDown` / `isReleasePostponed` / `isReleased`.
- Tests added: `VoiceTests::testSostenutoDoesNotHoldVoiceThatWasNotCaptured`, `testPedalReleaseDoesNotReleaseHeldKey`, `testSostenutoIsForgottenWhenPedalLifts` and `testStartClearsPedalState`. End to end through `doMIDIEvent` in `EngineTests` (each compares the rendering against a pedal-free reference sequence, sample for sample): `testSustainPedalTapDoesNotReleaseHeldKey` (with a non-vacuity guard), `testSustainPedalReleasesPostponedNoteWhenLifted`, `testSustainPedalLiftOnlyReleasesNotesWhoseKeysAreUp`, `testSostenutoPedalHoldsOnlyCapturedNotes` and `testSostenutoPedalTapDoesNotReleaseHeldKey`. The existing golden values in `testEngineSustainPedalProcessing` / `testEngineSostenutoPedalProcessing` did not change.
- Left over (step 2): `ReleaseKeyState::minimumNoteDurationSamples` is still ignored. It needs a per-voice sample counter and a deferred release in the render path. `releaseKeys_RT` (CC 123 All Notes Off) still releases unconditionally and ignores the pedals; the MIDI 1.0 spec says All Notes Off should honour sustain. Neither was changed here.

**Step 6 — done ahead of steps 3–5 at the user's request (2026-11-21). Committed as `e573b06` "Enable and wire up the low-pass filter (SF2.01 8.1.2 gens 8-11).";  `make test-macOS`: 278 tests, 0 failures.**
- Verified the filter design before enabling it. DSPHeaders `Coefficients::LPF2` (the Pirkle/RBJ form) has unity DC gain and gain Q at the cutoff. `DSP::centibelsToResonance` matches FluidSynth: Q = 10^((cB − 30.1)/200), so 0 cB gives a Butterworth response with no peak.
- `LowPassFilter::transform` no longer returns its input unfiltered. The API is now `needsUpdate()` / `update(fcCents, qCB)` / `transform(sample)`. Coefficients are recalculated every `updateInterval` (32) samples instead of every sample (the old code would have called sin/cos per sample whenever an LFO moved the cutoff). Each new set is ramped in over the same 32 samples with the DSPHeaders `Ramper`. The first update after `reset()` applies at once.
- Spec 8.1.2 #9, now implemented: the DC gain drops by half the Q value (100 cB → −5 dB). LPF2's numerator is scaled by `centibelsToAttenuationInterpolated(Q/2)`.
- Spec 8.1.2 #8, now implemented: Fc ≥ 13508 cents (~20 kHz) with Q ≤ 0 bypasses the filter. The filter keeps running while bypassed, so its state stays current and there is no click when the cutoff drops back.
- `Voice::renderSample` now computes Fc = initialFilterFc + modLfoToFilterFc·modLFO + modEnvToFilterFc·modEnv, all in cents (gens 8, 10, 11), and passes it with initialFilterQ. That also brings in the default velocity→Fc modulator (8.4.2), so notes below velocity 127 are now darker.
- Tests added in a new `LowPassFilterTests` (steady-state sine measurements at 48 kHz): the Butterworth response (unity at 20 Hz, −3 dB at the cutoff, < −34 dB three octaves above it); the cutoff tracking gen 8 from 100 Hz to 8 kHz; the DC gain −5 dB at Q 100 and −20 dB at Q 400; the peak/DC ratio equal to `centibelsToResonance`; the bypass rule; the update interval; and a full-range resonant sweep that stays finite, bounded and free of sample-to-sample jumps.
- End-to-end tests added in `EngineTests` (set through AU parameter events, then a note-on): `testLowPassFilterCutoffAttenuatesOutput` (Fc 1500 vs 13500), `testLowPassFilterResonanceLowersDCGain` (Q 200 → −10 dB ± 10 %), `testModEnvelopeToFilterCutoffOpensFilter` (1500 + 12000 from the mod envelope ≈ 13500 within 5 %) and `testModLFOToFilterCutoffModulatesFilter`.
- **Golden values regenerated:** 756 `XCTAssertEqualWithAccuracy` literals in 23 rendering tests (`EngineTests`, `VoiceTests`). Only lines that failed were changed. The new value is the actual rendered sample printed at 12 significant digits, captured by a temporary assertion override that was removed afterwards. Tolerances are unchanged. These values now encode the filtered output; the spec-based tests above are what show the filter is correct.
- Left over: `ENABLE_LOWPASS_FILTER` / `enableLowPassFilter` in `Package.swift` is still not referenced by any code, so it can't turn the filter off. Either wire it up or delete it. The spec says the resonant peak is Q cB above DC, but the FluidSynth-compatible mapping puts the gain at the cutoff at (Q − 3.01) dB. This is a deliberate deviation and should be documented. Render-performance numbers before and after were not compared. The README's "all generators supported" claim can be revisited now that gens 8–11 work.

**Step 3 — done (2026-11-21). Committed as `c38c541` "Honour sample start offsets (SF2.01 8.1.2 gens 0 and 4)."; `make test-macOS`: 288 tests, 0 failures.**
- `Sample::Index::start()` now starts at `bounds_.startPos()` instead of 0, so startAddrsOffset and startAddrsCoarseOffset (gens 0 and 4, SF2.01 8.1.2) take effect.
- Found and fixed while doing this: `Voice::configure` built the sample `Bounds` *before* `Engine::startVoice_RT` applied live AU-parameter overrides (`parameters_.applyChanged`), so none of the address-offset generators (0–4, 12, 45, 50) could be changed from the parameter tree. `Sample::Generator::configure` now only stores the sample span. The bounds are built in the new `Generator::start(const State&)`, which `Voice::start()` calls after all generator values are in place.
- `Bounds::hasLoop_` used to require `startLoopPos > startPos`. Now that the start offset is honoured, that would have disabled the loop for any start offset into the loop, cutting sustained notes short. The rule is now `startLoopPos < endLoopPos && endLoopPos <= endPos && startPos < endLoopPos`. The last term stops `Index::increment` from wrapping backwards when playback starts after the loop end.
- Tests added in a new `IndexTests`: start at 0, fine offset, coarse offset (2·32768 + 5), offset past the end (finished at once), restart returning to the offset, start inside a loop (still loops and wraps to the loop start), start past the loop end (no backwards jump, runs to the end), and `testGeneratorFirstSampleHonoursStartOffset`. That last test uses a real preset sample: with increment 1.0 and linear interpolation, the first two generated values equal span[N] and span[N+1] for N = 0, 1 and 500.
- End-to-end tests added in `EngineTests` (AU parameter, then a note-on through `doMIDIEvent`): `testStartAddressOffsetChangesRenderedNote` (2000 vs 0 differ, and resetting to 0 reproduces the reference exactly) and `testStartAddressCoarseOffsetPastEndOfSampleIsSilent` (silent output, voice count back to 0).
- Checked that the new tests catch the bug: with `whole_ = 0` put back temporarily, both engine tests and three `IndexTests` fail.
- Tests updated: three `BoundsTests` assertions (`testStartLoopOffset`, `testStartLoopOffsetCoarse`, `testEndLoopOffsetCoarse`) expected `hasLoop() == false` for a loop starting at sample 0. They now expect `true` because of the rule change above. No hard-coded rendering values changed, since none of the test presets use start offsets.
- Left over: §3.3 "Loop wrap at high pitch" and "Interpolation at loop end" in `Index::increment` / `Generator::sample` are still open. A start offset inside the loop makes the second more likely to matter, because `before()` can now be asked for `startLoopPos` on the first pass.

**Step 4 — done (2026-11-21). Committed as `b5256c8` "Harden SF2 parsing against malformed files and add a fuzz target."; `make test-macOS`: 308 tests, 0 failures. `make fuzz`: clean for 2 + 5 minutes (~3.2 M inputs) after the fixes below.**
- **noexcept:** removed from every function on the parse path that throws or calls code that throws: the `Entity::{Preset, Bag, Instrument, SampleHeader, Generator, Modulator}(Pos&)` constructors, `Version::load`, `Chunk::extract`, and the `ChunkItems` constructor and `load`. Malformed files now reach the `try/catch` in `File::load(int)` and return `invalidFormat` instead of terminating. `File::load(int)` also catches `std::exception` (e.g. `bad_alloc`). `Preset::loadSamples` stays `noexcept`: it now catches read errors itself and returns `false`, and `PresetsState` already treats that as "no active preset".
- **Empty chunks:** `ChunkItems::size()` / `end()` no longer underflow for an empty or missing chunk. A new `hasTerminal()` reports whether the terminal record was there. `load` replaces rather than appends, and rejects a chunk whose size is not a multiple of the entity size (spec 7.2–7.10). `Pos::makeChunkList` rejects a LIST size below 4. `ifil` must be 4 bytes.
- **File validation:** the new `File::validate()` runs after the RIFF walk. It requires at least one preset, plus terminal records in PHDR, PBAG, INST, IBAG and SHDR. PGEN/PMOD/IGEN/IMOD may be absent as long as no bag refers to them. It checks that PHDR→PBAG and INST→IBAG zone indices and PBAG/IBAG→gen/mod indices never decrease and that terminal records stay in range. Instrument links (7.5) and sampleID links (7.9) must be in range, and each linked sample header must have start ≤ end ≤ the number of samples in `smpl`. `sampleDataBegin_` is now limited to the `smpl` chunk (new `Pos::limit`), so headers can no longer read `pdta` bytes as audio.
- **Unknown generators (8.1):** `Generator::isValid()`, then `Zone::Collection::add` drops unknown generators before the zone is classified. `State::configureWith` also skips them as a second line of defence. `Generator::dump` handles them.
- **Invalid modulators (8.2):** `State::addModulator` ignores a modulator with an invalid amount source or a destination ≥ 59 (including the 2.04 link bit 15). `Modulator::makeValueProvider` has a `default:` case (inactive provider), which removes the UB for source 127.
- **Names:** `trim_property(char[N])` always leaves a terminating NUL, so a 20-character name is truncated to 19. `std::isspace` / `std::isprint` now get `unsigned char`.
- **Presets without samples:** `Preset::loadSamples` returns early for a preset whose zones have no samples (`maxEnd − minStart` underflowed). The padding after the last sample is now zero-filled instead of read from past the end of `smpl`.
- **Found by the fuzzer and fixed (render path, triggered by untrusted sample headers):** (1) A sample rate of 0 made `Pitch::configure` convert `log2(0) = −inf` to `int`, followed by integer overflows. It is now clamped to 400 Hz, per 7.10 ("the nearest practical value should be used"). (2) A heap-buffer-overflow read in `Generator::before()`: with `sampleModes` set but no usable loop (loop end 0 < loop start), cubic interpolation wrapped to `endLoopPos − 1` = −1. `Generator::generate` now only loops when `Bounds::hasLoop()`.
- **New test utility:** `Sources/TestUtils/SF2Builder.hpp`, a header-only plain C++ builder for small SF2 files. `minimal()` gives one preset → one instrument → one looped 441 Hz sine.
- **Tests added** in the new `MalformedFileTests` (19 tests), through both `File::load(fd)` and `Engine::loadFileAndPreset` + note-on:
  - the minimal file loads and plays; every truncation is rejected;
  - missing required chunks and a file with only the terminal preset are rejected, while missing modulator lists are accepted;
  - wrong chunk-size multiples, a bad `ifil` size and a LIST size below 4 are rejected;
  - out-of-range instrument and sample links, samples outside `smpl`, and five kinds of bad zone index are rejected;
  - unknown generators (59, 60, 1000, 0xFFFF) and invalid modulators (bad destination, link destination, bad amount source, source 127) are ignored: the rendering is identical to the clean file, and a non-vacuity check confirms that a valid CC→attenuation modulator does change it;
  - 20-character names are terminated and Latin-1 names are sanitised;
  - a preset with no samples is silent;
  - the two fuzz findings (sample rate 0 is identical to 400 Hz; an invalid loop is identical to no loop);
  - a deterministic 300-iteration random-corruption test that loads and plays each mutated file.
- **Checked that the tests catch the bugs:** with the step's source changes stashed, 7 of the new tests fail, and the process aborts on a libc++ bounds assertion in `testUnknownGeneratorsAreIgnored`. Each fuzz regression test also aborts with its fix removed.
- **Fuzz target:** `Fuzz/SF2FileFuzzer.mm` (libFuzzer + ASan + UBSan, `CHECKED_VECTOR_INDEXING=1`). It loads the input and, if that succeeds, builds presets, loads samples and renders voices. `Fuzz/MakeSeeds.cpp` writes three seeds. `make fuzz [FUZZ_TIME=s]` / `make fuzz-build` need Homebrew LLVM, because Apple clang ships without the libFuzzer runtime. Output goes to `.fuzz/` (added to `.gitignore`). `Fuzz/README.md` describes the target.
- **Also changed:** added the missing `#include <atomic>` to `PresetCollection.hpp`, which Homebrew's libc++ needs.
- No hard-coded rendering values changed.
- **Left over:**
  - `Source::isValid` still accepts general source 127. The `default:` case makes it harmless, but rejecting it belongs to step 7.
  - Sample headers marked as ROM samples are checked against `smpl` like any other, so a ROM-based file with out-of-range offsets is rejected.
  - The `ifil` major version is not checked.
  - `std::sort` of presets is still unstable (§3.3).
  - The `File::load()` / `Parser::parse` fd leaks belong to step 5.
  - `Zone::Zone` and `Zone::resourceLink` still `throw std::runtime_error`. Neither throw is reachable with validated input, but they are still exceptions in code reached from the render thread.
  - The fuzzer does not cover MIDI/SysEx input to `Engine::doMIDIEvent`. That would be a second target, after the SysEx fixes in §3.2.

**Step 5 — done (2026-11-21). Committed by the user as `a604806` "Do not leak file descriptors". `make test-macOS`: 318 tests, 0 failures.**
- New `IO::UniqueFd` (`SF2File/IO/UniqueFd.hpp`): a move-only owner of a POSIX descriptor that closes it on destruction. It has `openForReading(path)` (`O_CLOEXEC`), `duplicate(fd)` (`F_DUPFD_CLOEXEC`), `get()`, `isValid()` and `reset()`.
- `File` now owns its descriptor through a `UniqueFd fd_` member, replacing the unused `int fd_` and the hand-written destructor. `File(File&&) = default` now moves ownership instead of copying an int that would have been closed twice.
- `File::load()` (path) opens into a `UniqueFd` instead of leaking a descriptor on every load. `File::load(int fd)` now duplicates the caller's descriptor, so the caller keeps ownership and may close it right away. Both go through a private `load(UniqueFd&&)`, which keeps the descriptor only on success; on failure it is closed and `sampleDataBegin_` is reset.
- **Bookmark lifetime (§3.2):** this fixes it without any Engine logic change. In `beginLoadBookmarkAndPreset_RT`, the `NSFileHandle`'s descriptor can now be closed when the accessor block ends, and security-scoped access can stop. `File` keeps reading samples through its duplicate on later program changes, and can no longer read a reused descriptor that points at a different file. There is a comment at the call site.
- `Parser::parse` and `SF2FileInfo::load` no longer leak their descriptors (`UniqueFd`; `SF2FileInfo` relies on `File::load(int)` duplicating).
- Doc comments for `Engine::loadFileAndPreset(int, …)` and `SF2Engine::loadFileAndPreset(int, …)` now state the ownership rule. The stale "If -1, use the existing preset collection" claim is gone: the code never did that.
- Tests added in the new `FileDescriptorTests`:
  - `UniqueFd`: close on destruction, move construction and assignment, an independent duplicate, invalid inputs;
  - `File::load(path)` ×25 leaves exactly one descriptor per live `File` and none after;
  - failed loads leak nothing;
  - `testLoadFromDescriptorSurvivesCallerClosingIt`: after the caller closes its descriptor, with and without the number being reused by `/dev/zero`, the loaded samples are identical to a by-path load;
  - a moved `File` keeps a single descriptor;
  - `Parser::parse` leaks nothing, whether it succeeds or throws.
- In `FileInfoTests`, `testLoadingDoesNotLeakDescriptors` was added.
- End to end in `EngineTests`, `testProgramChangeAfterBookmarkLoadReadsSamples` loads by bookmark inside an `@autoreleasepool` (so the `NSFileHandle` really is released), lets the descriptor number be reused, then sends MIDI program change 23 and a note. The rendering must match the same sequence after a by-path load, sample for sample.
- Checked that the tests catch the bugs: on the pre-step-5 sources, all five leak tests fail. The descriptor-survival and bookmark tests fail too: `loadSamples` returns false, and the bookmark engine ends up with no active preset and renders silence. The first versions of those last two tests passed on the old code, because of descriptor reuse and autorelease timing. They were strengthened before committing.
- No hard-coded rendering values changed.
- Left over:
  - `Config::samples()` (and `PresetsState::activePreset()`, `Zone::resourceLink()`) still `throw std::runtime_error`. They are unreachable when sample loading succeeds or the preset is made inactive, but they are still exceptions on render-thread paths (§4).
  - The use-after-free and leak of old `PresetsState`s on file switch (§3.2) belong to step 8.
- Since this step, the user switched `SF2::Float` to `float` (`b762bf3`, `f2f90bd`, DSPHeaders 1.6.1). That is step 9's sample-storage idea applied to all processing. Because DSPHeaders' `_F` literal still yields `double`, mixed-type `std::max` / `std::clamp` / `ConstMath::pow` calls need an explicit `<Float>`.

**Step 7 — done (2026-11-22). Committed as `537b322` "Support preset modulators; "No Controller" = 1; reject reserved sources."; `make test-macOS`: 326 tests, 0 failures.**
- **PMOD support (7.4, 9.5.1):** the new `State::addPresetModulators(globalPreset, preset)` is called from `Config::applyTo` after the instrument and preset generators. A global preset zone modulator is skipped if the local preset zone has an identical one. Within a zone, the last of several identical modulators wins (7.4). Each remaining preset modulator goes through `addPresetModulator`, which adds its amount to an identical modulator already installed (instrument level or default), using the new `Modulator::addAmountFrom`, or appends it as a new modulator. Instrument-level replacement (`addModulator`) is unchanged.
- The validity checks from step 4 are now `State::isUsable` and apply to preset modulators too.
- **"No Controller" = 1 (8.2.1):** `Modulator::value` now treats an inactive primary source as 1 instead of returning 0, so a source-less modulator applies `amount × amount-source` as a constant. The amount source already behaved this way. The `Entity::Modulator` doc comment that said 'none' returns 0.0 is corrected.
- **Reserved sources (8.2.1):** `Source::isValid` now rejects general index 127 (a 2.04 link). It also rejects CC 99 and 100: the spec makes 98–101 illegal, but only 98 and 101 were rejected. The `default:` case in `makeValueProvider` can no longer be reached for usable modulators.
- **Tests added**, in a new `PresetModulatorTests` (8 tests). Each builds two files with `SF2Builder` that the spec says must be equivalent, renders a note through the Engine (with CC 16 / CC 17 set), and requires identical output. Each also checks that the modulator under test really changes the sound:
  - preset 100 + instrument 200 ≡ instrument 300;
  - a preset modulator with no match ≡ the same instrument modulator;
  - a preset amount of −960 on the default velocity→attenuation modulator ≡ an instrument modulator replacing it with 0;
  - local preset supersedes global (≡ local only, ≠ summed);
  - an un-superseded global preset modulator is added;
  - duplicate preset modulators: last wins;
  - a "No Controller" modulator of 200 cB ≡ the initialAttenuation generator at 200, at both instrument and preset level;
  - reserved general and CC sources, including as the amount source, are ignored.
- **Tests updated:** `ModulatorSourceTests` now expects 127 to be invalid, and adds 38 and 99/100 to the illegal CCs.
- **Checked that the tests catch the bugs:** on the pre-step sources, 7 of the 8 new tests and both updated source tests fail. The eighth (duplicates) passed vacuously until it was given its own non-vacuity check.
- No hard-coded rendering values changed: none of the test presets use PMOD or "No Controller" sources.
- **Left over:**
  - Modulator identity (`Entity::Modulator::operator==`) still ignores the transform. 9.5.1 includes it, while 7.4 lists only the three enumerators. It only matters once a second transform (2.04 "absolute value") is supported.
  - Unknown `sfModTransOper` values are not checked.
  - `State::modulators_` still grows with `emplace_back` at voice start, an allocation on the render thread (§4, step 8).

**Step 8 — done (2026-11-22). Committed as `984e8fc` "Real-time safety: PresetsState lifetime, async program change, SysEx."; `make test-macOS`: 338 tests, 0 failures. (`make test-iOS` was not re-run: it locked up Xcode during this step. The user's `-collect-test-diagnostics never` Makefile change addresses the `simctl diagnose` stall.)**
- **PresetsState lifetime (§3.2 use-after-free and leaks):**
  - Each `PresetsState` now has a generation number. The `past_` pointer and `deletePast()` (which ran `delete` on the render thread at note-on, freed only one level, and could free samples that releasing voices still played) are gone.
  - Loaders build the new state and load its active preset's samples before publishing it with `installPresetsState_WQ`. That moves the old state onto `retired_` (under `retiredMutex_`, never touched by the render thread).
  - At each render-thread entry point (`renderInto`, `noteOn_RT`, `changeProgram_RT`), `syncPresetsState_RT` compares generations. If a new state has appeared, it stops all voices and stores the generation in `renderGeneration_`.
  - A retired state is freed (on the loader's thread) only once its generation is below that acknowledged generation. `doRenderingStateChanged(false)` frees all retired states. The new `Engine::~Engine` drains the work queue and frees everything.
  - `activePresetOrNull()` gives a non-throwing accessor for the render thread.
- **Program change off the render thread (§4, §3.2 hang):**
  - `changeProgram_RT` now returns early when nothing is loaded. It used to bump `presetChangesPending_` first and never undo it, which blocked note-on forever.
  - Otherwise it stops the voices, stores the located preset index in `requestedPresetIndex_`, bumps the pending count, and queues `usePresetRequest_WQ` with `dispatch_async_f`: a plain function pointer, so no block copy or Objective-C runtime on the render thread. The disk reads and the allocation now happen on the work queue.
  - Repeated requests for the already-active preset are skipped.
  - `usePresetWithIndex_WQ` no longer dereferences a possibly-null `ptr`, or builds an `NSString` for logging.
- **Bookmark load hang:** `beginLoadBookmarkAndPreset_WQ` now undoes `presetChangesPending_` on every path that does not load (bookmark resolve error, nil URL, coordination failure, unreadable file). It also no longer dereferences `presetsState_` without a null check.
- **Naming (§4):** functions that run on the work queue or a caller's thread were renamed from `_RT` to `_WQ`: `beginLoadFileAndPreset_WQ`, `beginLoadBookmarkAndPreset_WQ`, `concludeLoad_WQ`, `usePresetWithIndex_WQ`, `bumpLastLoadFinished_WQ`.
- **Voice start/stop:** `updateActiveVoiceCount_RT` (an `AUParameterTree` lookup and `setValue:` on every voice start and stop) is removed. `provideParameterValue` already reports the live count, and `testEngineActiveVoiceCount` (which reads `param.value`) still passes.
- **No allocation at note-on:**
  - `Preset::find` now fills a `Utils::FixedCapacityVector<Config, 64>` (new `SF2Util/FixedCapacityVector.hpp`: inline storage and placement-new, so `Config`'s reference members are fine) using the new non-allocating `Zone::Collection::visit`. Any zones beyond 64 are dropped and logged.
  - `State` reserves 64 modulator slots at construction.
  - `Zone::Instrument::samples()` no longer throws (it is reached through `noexcept Config::samples()`), and `startVoice_RT` skips a zone without samples.
- **SysEx (§4, part of §3.2):**
  - `doMIDIEvent` checks the length before reading `data[1]`/`data[2]`.
  - `queueSysExRequest_RT` only copies the message into one of four preallocated 8 KB `SysExRequest` slots (or drops it if all are busy), stops voices, bumps the pending count, and queues `processSysExRequest_WQ` with `dispatch_async_f`.
  - The work queue bounds `overrideCount` by the bytes actually present (previously an out-of-bounds read and copy), Base64-decodes, and creates the bookmark with `[[NSData alloc] initWithBase64EncodedData:…]`. That fixes the `init`-on-an-initialised-object UB.
  - Every rejection undoes the pending count.
- **Tests added** in the new `RealTimeSafetyTests` (11) and `FixedCapacityVectorTests` (1):
  - **No allocation on note-on:** the test replaces global `operator new` in the test bundle with a per-thread counter, then plays a 4-note chord and renders 11 blocks. That must make zero C++ allocations.
  - **Program changes:** with the work queue suspended, a program change stops voices, holds the pending count at 1, keeps the old preset, and ignores note-ons; after resuming, the new preset plays. A program change with nothing loaded no longer blocks notes.
  - **Bookmark failure:** a bookmark that does not resolve does not block notes.
  - **State lifetime:** after a load, the old state stays retired while its voice sounds and is stopped at the next render. Over 10 load/note/render cycles, at most one state waits, and none after rendering stops.
  - **SysEx:** messages shorter than the header are ignored; a 10⁹ override count and invalid Base64 are rejected; SysEx loads still work; a fifth request while the queue is held is dropped.
  - **Capacity:** an instrument with 70 overlapping zones starts exactly 64 voices.
  - **`FixedCapacityVector`:** capacity, `at`, copy, move and destruction with a non-default-constructible, non-assignable type.
- **Tests updated:** `testEngineChangePresetByBankProgram` now calls `drainWorkQueue()` after each program change. The user had already added the same to `testEngineMIDIProgramChange` and `testProgramChangeAfterBookmarkLoadReadsSamples`; those had been passing only by winning the race. New harness helpers: `suspendWorkQueue()`, `resumeWorkQueue()` and `retiredPresetsStateCount()`.
- **Checked that the tests catch the bugs:**
  - With the vector-building `Preset::find` restored, the chord makes 8 allocations.
  - With `++presetChangesPending_` moved back in front of the null check, the nothing-loaded test fails on both assertions.
  - A full revert of the step does not compile against the new harness helpers.
- No hard-coded rendering values changed.
- **Behaviour change:** a MIDI program change now completes asynchronously. Until the preset's samples are loaded, nothing renders and note-ons are ignored. This is the same gating SysEx loads already used.
- **Left over:**
  - `dispatch_async_f` on the render thread can still allocate a libdispatch continuation on a cache miss. A preallocated lock-free queue plus a waiting worker thread would remove even that.
  - The direct API `loadFileAndPreset("", index)` (`usePresetWithIndex_WQ`) changes the samples of the published state without the render thread stopping voices first. It is only safe while not rendering, or when called after a render-thread program change. Make it go through the render thread (or a new state) if hosts use it while playing.
  - Non-render-thread accessors (`activePresetName()` etc.) read the published state without a reference, so a concurrent load and render-thread acknowledgement could free it underneath them. The window is tiny but real.
  - `parameters_.reset()` runs on the work queue while the render thread reads `parameters_` (a pre-existing data race).
  - The `os_log_info` calls on per-event paths are unchanged.
  - The SysEx payload still carries raw 8-bit `size_t` fields and uses manufacturer 0x7E (§3.2 protocol issues), and the generator overrides are still parsed but not applied.
  - `Engine::Engine` still only `assert`s `voiceCountLimit <= maxVoiceCount` (§3.2).

**Step 9 — done (2026-11-22). Committed as `0d2df03` "Tighten float test tolerance; regenerate sample values for float."; `make test-macOS`: 338 tests, 0 failures.**
- **The switch itself was done by the user** in `b762bf3` ("Move back to doing all audio processing in Float instead of Double. Using latest DSPHeaders.") and `f2f90bd`/`630d65d` ("Simplify."). `SF2::Float` is now `float`, so `SampleVector` (`std::vector<Float>`) stores samples as 32-bit floats, half the memory of `double`. The render math is `float` too, matching the AU output format. Because DSPHeaders' `_F` literal is always `double`, a few mixed-type `std::max` / `std::clamp` / `ConstMath::pow` calls needed an explicit `<Float>`.
- **What this step fixed: the test tolerance had silently loosened.** `PresetTestContextBase::epsilonValue()` returns `1.0e-3` when `Float` is `float` (versus `1.0e-12` for `double`). So the switch widened the tolerance of all 1,144 tolerance-based assertions from 1e-12 to 1e-3, without any test changing. For rendered samples, which are typically 0.001–0.1, that tolerance let real regressions through. Tightened to `1.0e-6`, 636 assertions failed: 631 rendering values that had never been regenerated after the switch (median error 8.7e-6, 294 above 1e-5, worst 5.9e-4, about 1% of the sample), and 5 modulator values.
- **Regenerated:** the 631 hard-coded rendering values in `EngineTests` (591) and `VoiceTests` (40), from the actual `float` output printed at 12 significant digits. They were captured with a temporary assertion override that has since been removed. Only lines that failed were changed. Two values whose output lines were split by interleaved XCTest output were recovered by hand and checked against the 6-digit actuals in the failure messages.
- **`ModulatorTests`:** 5 assertions compare values of 119–12,599 cents/cB. An absolute 1e-6 is finer than a `float` can resolve there (its spacing is about 8e-6 at 119 and 1e-3 at 12,600), so they now use `relativeAccuracy(x) = |x| × 1e-6`, a few float ULPs. That is far tighter than the 1e-3 absolute they had been running with.
- **Float epsilon is now 1e-6.** That is about 10–100× a float ULP for typical sample values, and leaves room for small differences between CPUs and Accelerate versions while still catching the 1e-5 drift above.
- No source code changes in this step: only `Sources/TestUtils/SampleBasedContexts.hpp` (the tolerance) and test values.
- **Left over:**
  - §6.1's further option, keeping samples as `int16` and scaling during interpolation (a quarter of the original `double` footprint), was not done. Neither was §6.7's per-sample-header loading, which avoids loading the whole `[minStart, maxEnd]` range for scattered drum kits.
  - An SF2-specific `_F` literal returning `Float` would remove the explicit `<Float>` template arguments.
  - §2's diagram still says `SampleVector<double>`.

**Follow-up (2026-11-22): SF2.01 8.2.1 source 16, RPN 0 pitch-wheel sensitivity. Not yet committed. `make test-macOS`: 344 tests, 0 failures.**
- `ChannelState::setContinuousControllerValue` now tracks RPN selection: CC 101/100 select it (the RPN null 127/127 deselects), and selecting an NRPN deselects it. A Data Entry MSB (CC 6) with RPN 0 selected sets `pitchWheelSensitivity_` in semitones. That is the value of modulator source 16, which the default pitch-wheel modulator (8.4.10) uses as its amount source.
- RPN selection is kept separate from the NRPN decoder. An unrelated CC does not deselect an RPN, as MIDI requires; the NRPN decoder still cancels on unrelated CCs (§3.3, still open).
- Not handled: the Data Entry LSB (extra cents, which the semitone-resolution source cannot represent), Data Entry increment/decrement (CC 96/97), and other RPNs.
- The header's default for `pitchWheelSensitivity_` is corrected to 2. It said 200, although `reset()` always set 2. The `setPitchWheelSensitivity` doc comment now gives the unit as semitones.
- Tests added:
  - `ChannelStateTests::testRPN0SetsPitchWheelSensitivity`: RPN 0 sets the value, the Data Entry LSB does not change it, and an intervening CC 1 does not deselect.
  - `ChannelStateTests::testRPNDataEntryOnlyAppliesToRPN0`: Data Entry is ignored with nothing selected, with RPN 1, after the RPN null, and after an NRPN is selected; `reset()` restores 2.
  - `EngineTests::testRPN0PitchWheelSensitivityControlsBendRange` (end to end through `doMIDIEvent`): with RPN 0 = 0, a full bend renders identically to no bend, whether RPN 0 is sent before the note or while it sounds; with RPN 0 = 2, it matches the default; 12 differs from both.
- With the RPN data-entry handling disabled, all three tests fail.
- **Behaviour change:** hosts that send RPN 0 now get the bend range they ask for, instead of a fixed 2 semitones.
- **Left over:** MIDI RP-015 says Reset All Controllers (CC 121) should not reset RPN values, but `reset_RT` → `ChannelState::reset()` puts the sensitivity back to 2.


**Follow-up (2026-11-22): NRPN cancellation (§3.3) and CC 121 Reset All Controllers. Not yet committed. `make test-macOS`: 349 tests, 0 failures.**
- **NRPN:** `ChannelState::decodeNRPN` no longer ends SF2 NRPN decoding when any other controller arrives. Per SF2.01 9.6.2, only CC 99 (NRPN) and CC 101 (RPN) change the Data Entry mode, so a mod wheel, pedal or volume message between the NRPN select and its Data Entry no longer drops the value. Data Entry is still applied when the MSB arrives, combined with the most recent LSB: 9.6.3 specifies exactly that, so the "LSB after MSB is ignored" part of the §3.3 note is spec behaviour, not a bug.
- **CC 121:** this used to call `reset_RT()` (stop every voice and power-on reset of the channel state, including bank select and pitch-wheel sensitivity). It now calls the new `Engine::resetAllControllers_RT()`, which uses the new `ChannelState::resetControllers()` and follows MIDI RP-015.
  - Reset: modulation (CC 1/33) to 0, expression (CC 11/43) to 127, the pedals (CC 64–67) to off, the RPN/NRPN numbers to null, pitch bend to centre, and channel and key pressure to 0.
  - Kept: bank select, volume, pan, the sound and effects controllers, and the RPN/NRPN values (pitch-wheel sensitivity and the SF2 NRPN generator offsets).
  - Voices keep sounding with the reset values. Notes held only by sustain or sostenuto are released through the normal pedal-release path.
  - The MIDI System Reset message (0xFF) still calls `reset_RT()`.
- **Tests added:**
  - `ChannelStateTests::testUnrelatedControllersDoNotCancelNRPN`: CC 1, CC 64 and CC 7 between the select and the Data Entry; the value still lands, and the other controllers still apply.
  - `ChannelStateTests::testResetControllersFollowsRP015`: every reset and kept item, plus Data Entry having no effect after the reset.
  - End to end through `doMIDIEvent` in `EngineTests`:
    - `testResetAllControllersReleasesPedalHeldNotes`: CC 121 sounds identical to lifting the sustain pedal at the same time.
    - `testResetAllControllersKeepsHeldNotesSounding`: identical to sending no CC 121.
    - `testResetAllControllersRecentresBendButKeepsBendRange`: identical to sending a centre bend; an RPN 0 range of 12 survives CC 121.
- **Tests updated:** `testEngineResetAllControllers` expected bank select to be reset and the voice stopped. Both contradict RP-015; it now expects the opposite.
- **Checked that the tests catch the bugs:** with the NRPN cancel and the old `reset_RT()` call put back, all 6 new or updated tests fail (9 assertions).
- **Behaviour change:** CC 121 no longer silences notes, and no longer resets bank select or the pitch-bend range.
- **Correction (2026-11-22):** an earlier version of this entry said "RP-015 also lists Legato (CC 68) and Hold 2 (CC 69) in some revisions, and General MIDI 2 adds others". That was stated from memory and is not supported: the RP-015 table as reproduced in secondary sources (approved May 1999), and the Yamaha XG equivalent, list exactly the controllers reset above. One search summary also attributed to RP-015 the rule "all other controllers should be set to 0, otherwise the behavior should be documented", but this could not be confirmed in any fetched text. The primary RP-015 document (midi.org) was not available. Controllers that RP-015 lists in neither group are therefore left unchanged, and `ChannelState::resetControllers` and its header comment now say so explicitly. No behaviour change.

**Follow-up (2026-11-22): SF2.01 8.1.2 #34, convex volume envelope attack. Not yet committed. `make test-macOS`: 352 tests, 0 failures.**
- The attack used to ramp the normalised-dB envelope value linearly from 0 to 1. The voice maps that value to `960 × (1 − v)` cB, so the attack was linear in dB: −48 dB half way through, rising sharply at the end. The spec asks for the result to be "linear in amplitude".
- New `Envelope::volumeEnvelopeAttackCurve(progress) = centibelsToVolumeEnvelope(−200 · log10(progress))`, the normalised-dB value whose gain equals `progress` (0 below the 96 dB floor).
- `Envelope::Generator` gained `enableConvexAttack()` and an `attackProgress_`. When it is enabled, the attack stage ramps `attackProgress_` linearly and sets `value_` to the curve. Because `value_` holds the shaped value, a note-off during the attack releases from the level being heard, with no extra conversion. `Envelope::Volume` enables it; `Envelope::Modulation` does not.
- The cost is one `log10` per voice per sample, during the attack only. The voice's gain path is unchanged.
- Tests:
  - `EnvelopeTests::testAttack` now expects the curve values, and checks that the exact gain of each value equals the progress (to 1e-5 relative).
  - `testAttackAborted` now expects the release to continue from the shaped value.
  - Added `testAttackCurveShape` (half way = 60.206 cB; clamping) and `testModulationEnvelopeAttackStaysLinear`.
  - End to end: `EngineTests::testVolumeEnvelopeAttackIsLinearInAmplitude` plays the `SF2Builder` sine with a 1 s attack. The RMS level at 25%, 50% and 75% of the attack, relative to the level after it, must be 0.25 / 0.5 / 0.75 within 3%. That allows for the 1 cB resolution of `centibelsToAttenuation` and the measurement window.
- With the convex attack disabled, all three changed tests fail.
- No hard-coded rendering values changed: the bundled test presets' attacks are too short to affect the values sampled.
- **Behaviour change:** notes with a non-zero volume attack time now rise linearly in amplitude, so they are louder early in the attack and reach full level smoothly.

**Follow-up (2026-11-22): gen 54 sampleModes looping (§3.3 loop wrap and interpolation). Not yet committed. `make test-macOS`: 356 tests, 0 failures.**
- **Loop wrap:** `Sample::Index::increment` used to subtract `loopSize()` once at the loop end. With an increment larger than the loop (a short loop played at a high pitch), the position stayed past the loop end and drifted forward. The end-of-sample check is only on the non-looping branch, so it read past the end of the sample buffer. The position now wraps by modulo: `startLoop + (whole − endLoop) % loopSize`.
- **Interpolation at the loop end:** `Sample::Generator::sample()` used to wrap only `whole == endLoopPos`, but cubic interpolation also reads `whole + 2`. Every read at or past the loop end now wraps the same way.
- **Interpolation at the loop start:** `Sample::Generator::before()` used to substitute the loop-end sample at the loop start on the very first pass, before any looping had happened. It now does so only once playback has wrapped. That is captured as `hasLooped` *before* the index is incremented, and the interpolator functions take it as an extra parameter.
- **Tests added:**
  - `IndexTests::testLargeIncrementStaysInsideShortLoop`: an increment of 100 on a 47-sample loop, for 200 steps.
  - `IndexTests::testCubicInterpolationAcrossLoopBoundaries` (increment 1.5) and `testCubicInterpolationWithIncrementLargerThanLoop` (increment 40.25 on a 16-sample loop). These run the real `Sample::Generator` over a synthetic sample whose values encode their index, and compare every output with a reference model of the correct wrap rules.
  - `EngineTests::testShortLoopAtHighPitchKeepsLooping`: a 4-sample loop played 3 octaves up stays active, with finite, bounded output that is still sounding at the end of 0.5 s.
- **Checked that the tests catch each bug,** by putting back each old behaviour on its own:
  - the single subtraction fails the index test, the large-increment reference test and the engine test;
  - the exact-end-only wrap fails both reference tests;
  - the first-pass loop-start wrap fails the 1.5 reference test.
- No hard-coded rendering values changed: none of the sampled values fall on a loop boundary.

**Follow-up (2026-11-23): SF2.01 8.1.2 #57 exclusiveClass. The first part was committed by the user as `9deb75b`; the review fixes are `9a7c323`. `make test-macOS`: 359 tests, 0 failures.**
- **`9deb75b` (user):**
  - `Config` reads `exclusiveClass` from the global instrument zone, and the local zone overrides it.
  - `Engine::stopAllExclusiveVoices_RT` calls the new `Voice::releaseKeyViaExclusiveClass()` instead of stopping the voice.
  - That calls the new `Envelope::Generator::noteAborted()`, which enters a release of `noteAbortReleaseDuration` (5 ms) from the current value.
  - `TestEngineHarness` was refactored to render by time (`renderForDuration`, `renderForCount`, `renderMaxFramesCount`), and the hard-coded rendering values in `EngineTests` and `VoiceTests` were regenerated for it.
- **Review fixes:**
  - **5 ms fade never happened:** the abort length was only set by the test-only constructor. Voices are built with the default constructor, so the "fade" lasted one sample. `configureVolumeEnvelope` and `configureModulationEnvelope` now set it from the sample rate.
  - **Released notes were not cut off:** `releaseKeyViaExclusiveClass` returned early for a voice already in its release phase, so an open hi-hat ringing out was not choked. The spec says "any other sounding note", so it no longer returns early. `noteAborted` also shortens a release that is already running.
  - **Mod envelope stopped outright:** the modulation envelope was stopped, which made its pitch and filter effect jump during the fade. It now gets the same 5 ms release.
  - `playAudioDuringTests` went back to `false`.
- **Tests:**
  - `EngineTests::testEngineExcludeClassNoteTermination` used to assert that the old voice was gone after 4 ms, which only passed because of the one-sample fade. It now requires the old voice to be active 1 ms after the new note and gone 5 ms later. (It stops after about 2 ms: the voice's gain includes the velocity attenuation, so it reaches the −80 dB cut-off early.)
  - Added `EngineTests::testExclusiveClassChokesReleasingNote`: a note released 10 ms earlier is choked by a new note in its class.
  - Added `EnvelopeTests::testVolumeEnvelopeNoteAborted` and `testModulationEnvelopeNoteAborted`. These configure from a voice state (the production path), with a 2 s release. Aborting while sustaining must start just below 1.0 and finish in about 240 samples. Aborting part way through the release must continue from the current value and finish just as quickly.
  - `testResetAllControllersRecentresBendButKeepsBendRange` and `testSostenutoPedalHoldsOnlyCapturedNotes` had their key assertions commented out. After the harness refactor their event times were render-block indices being read as seconds, so the sequences no longer meant what they said. They now use `blocks(n)` durations matching the original timing, both assertions are back, and both pass. The bend test also gained a check that the bend is actually heard (`centred != bentThroughout`).
- **Checked that the tests catch the bugs:**
  - with the abort length left at 0, both engine tests and both envelope tests fail;
  - with the early return on `released_` put back, `testExclusiveClassChokesReleasingNote` fails.
- **Left over:** no test catches `Voice::releaseKeyViaExclusiveClass` stopping the modulation envelope instead of aborting it. That would need a preset with a mod envelope routed to pitch or the filter, and a way to separate the old voice's output from the new one's.
- No hard-coded rendering values changed with the review fixes: none of the sampled tests trigger an exclusive class.
- **Behaviour change:** notes cut off by an exclusive class now fade out over 5 ms or less instead of stopping with a click, and this also applies to notes in their release phase.

**Follow-up (2026-11-23): SF2.01 7.4 / 8.3 / 9.5.1 / 10.3 modulator transforms. Commit `067af28`. `make test-macOS`: 367 tests, 0 failures.**
- **Unknown transforms:** `Transformer` used to keep the raw value but always report and apply "linear", so a modulator with an unknown `sfModTransOper` still had its effect. 7.4 ("Unknown or undefined values are ignored") and 10.3 ("unknown enumerators should simply cause the associated Generator or Modulator to be ignored") ask for the whole modulator to be dropped. `Transformer::isValid()` is new, and `State::isUsable` now rejects such modulators, the same way it rejects reserved sources. Throwing from the parser was considered and rejected: it would refuse files that the spec says must load (5.1: unknown transform enumerators are "defined as being ignored if unknown").
- **Absolute value (SF2.04, transform 2):** `Transformer::Kind::absolute` is new. `Render::Voice::State::Modulator::value` applies the transform to the product `Amount × Map(primary) × Map(secondary)`, as in 9.5.1's `Transform(...)` equation and 8.3 ("the output value of the multiplier"). FluidSynth does the same.
- **Identity:** 9.5.1 defines identical modulators by "source, destination, amount source, and transform"; 7.4's in-zone duplicate rule uses only the first three. `Entity::Modulator::operator==` now includes the transform, and is used where one level supersedes or adds to another (defaults → global instrument → local instrument; preset adds to instrument; local preset supersedes global preset). The new `hasSameEnumerators` is used by `isShadowed` for duplicates within one zone. Instrument zones now go through `isShadowed` as well. Before, they relied on `addModulator` replacing an equal modulator, which with a transform-aware `==` would have kept both duplicates.
- **Tests added:**
  - `EntityModulatorTransformTests` (new file): linear, absolute, unknown kinds (invalid, printed as `unknown(n)`), and identity with and without the transform.
  - `PresetModulatorTests::testUnknownTransformsAreIgnored`: transforms 1, 3 and 0xFFFF at instrument and preset level render the same as no modulator; the linear version does not.
  - `testAbsoluteValueTransform`: |−300 × CC16| renders like +300 × CC16 at both levels, and unlike −300.
  - `testPresetModulatorWithDifferentTransformIsNotSummed`: an absolute −300 instrument modulator plus a linear +600 preset modulator renders like +900, not like the summed |300|.
  - `testDuplicateInZoneIgnoresTransform`: in instrument and preset zones, a later modulator with the same three enumerators but a different transform replaces the earlier one.
- **Checked that the tests catch each bug,** by putting back each old behaviour on its own: no validity check; transform not applied; identity without the transform; in-zone shadowing by identity; instrument zones without `isShadowed`. Each makes at least one new test fail.
- No hard-coded rendering values changed: the bundled test files use only linear transforms.
- **Behaviour change:** modulators with unknown transforms no longer have any effect; SF2.04 files using the absolute-value transform now sound as intended.

**Follow-up (2026-11-23): SF2.01 10.5, out-of-range values after summation. Not yet committed. `make test-macOS`: 373 tests, 0 failures.**
- **Correction:** `f57b707` marked this row ✅ with a description of central clamping in `State::unmodulated` / `State::modulated`. That code was never committed: `GenValue::modulated()` returned the raw sum. The row now describes what is actually implemented, below.
- **Approach:** 10.5 says out-of-range values, including ones that result from summation, "should be handled by substituting the nearest perceptually relevant or realizable value". Each consumer clamps instead of `State::modulated` doing it centrally. Central clamping would also clamp fineTune to ±99 cents and break pitch bend, since the default pitch-wheel modulator targets fineTune (as in FluidSynth).
- **New `State::modulatedInRange(gen)`:** clamps the modulated value to `Definition::valueRange()`. Used for:
  - `Pitch::samplePhaseIncrement`: coarseTune (±120) and mod LFO, vibrato LFO and mod envelope to pitch (±12000). fineTune is not clamped.
  - `Voice::renderSample`: modLfoToVolume (±960) and the mod LFO / mod envelope to filter Fc depths (±12000). The final cutoff keeps its own realisable bound in `LowPassFilter::update`.
  - `midiKeyEnvelopeScaling`: the four keynumTo* generators (±1200), before they are scaled by the key. The resulting times were already clamped.
- **New `DSP::lfoDelayTimecentsToSeconds`:** LFO delays clamp to [−12000, 5000], but −32768 or lower means no delay, as for the envelope delays (`LFOTests::testConfigFromState` relies on that). It is used by `ModLFO` and `VibLFO`.
- **Already bounded and left alone:** envelope times and sustain levels, LFO frequencies (`lfoCentsToFrequency`), filter Fc and Q, initial attenuation, pan, and the chorus and reverb sends.
- **Tests:**
  - `PresetModulatorTests`: `testCoarseTuneSumIsClamped`, `testPitchModulationDepthSumIsClamped` (vibrato and mod LFO), `testModLFOToVolumeSumIsClamped`, `testModLFOToFilterCutoffSumIsClamped` and `testKeyToVolumeEnvelopeDecaySumIsClamped`. Each renders a generator at the edge of its range plus a constant "No Controller" modulator that pushes it further. That must sound the same as the generator alone, and different from not having the generator.
  - `DSPTests::testLFODelayTimecentsToSeconds`.
- **Checked that the tests catch the bug:** with no clamp in `modulatedInRange`, all 5 render tests fail. With the clamp removed from just `Pitch.hpp`, `Voice.hpp` or `Generator.mm`, the tests for that file fail.
- **Left over:** no render test covers the LFO delay clamp. Any delay above 5000 timecents is about 18 s, far longer than a test render. The DSP unit test covers it.
- No hard-coded rendering values changed.
- **Behaviour change:** sums that go out of range now saturate at the generator limit, instead of producing more extreme pitch, LFO volume or filter swings and longer or shorter key-scaled envelopes.
