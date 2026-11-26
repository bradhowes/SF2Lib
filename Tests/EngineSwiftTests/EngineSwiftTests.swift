// Copyright © 2026 Brad Howes. All rights reserved.

import Engine
import Foundation
import Testing

/// The sound fonts bundled with TestUtils, located from this source file so that this target does not need to import
/// TestUtils (which would expose its internal C++ headers to Swift).
private let resources = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .deletingLastPathComponent()
  .appendingPathComponent("Sources/TestUtils/Resources")

private let freeFontPath = resources.appendingPathComponent("FreeFont.sf2").path

/// Exercises the `Engine` module from Swift, so that the C++ interop surface (initialisers, `const` methods, subscripts,
/// `std::optional`, non-copyable types) is compiled and checked from the Swift side.
@Suite struct EngineSwiftTests {

  @Test func engineMethodsAreNonMutating() {
    // A `let`: this only compiles if every method used is `const` in C++ (imported as non-mutating).
    let engine = SF2Engine()
    #expect(engine.loadFileAndPreset(std.string(freeFontPath), 0) == .ok)
    #expect(String(engine.activePresetName()) == "Piano 1")
    #expect(engine.activeVoiceCount() == 0)
    #expect(engine.retriggerModeEnabled())
  }

  @Test func engineCopiesShareTheEngine() {
    let first = SF2Engine()
    let second = first
    #expect(first.loadFileAndPreset(std.string(freeFontPath), 2) == .ok)
    #expect(String(second.activePresetName()) == "Piano 3")
  }

  @Test func engineReportsLoadFailures() {
    let engine = SF2Engine()
    #expect(engine.loadFileAndPreset(std.string("/does/not/exist.sf2"), 0) != .ok)
  }

  @Test func payloads() {
    let payload = Array(SF2Engine.createLoadFileUsePresetPayload(std.string(freeFontPath), 1, []))
    #expect(payload.first == 0xF0)
    #expect(payload.last == 0xF7)
  }

  @Test func fileInfoLoadsAndIndexes() {
    var info = SF2FileInfo(std.string(freeFontPath))
    #expect(info[0].value == nil)  // nothing before `load`
    #expect(info.load() == .ok)
    #expect(info.size() == 235)
    #expect(String(info.embeddedName()) == "Free Font GM Ver. 3.2")

    let first = info[0].value
    #expect(first.map { String($0.name()) } == "Piano 1")
    #expect(first?.bank() == 0)
    #expect(first?.program() == 0)

    let last = info[234].value
    #expect(last.map { String($0.name()) } == "SFX")
    #expect(last?.bank() == 128)
    #expect(info[235].value == nil)  // out of range: no value instead of reading past the end
  }

  @Test func fileInfoReportsMissingFile() {
    var info = SF2FileInfo(std.string("/does/not/exist.sf2"))
    #expect(info.load() == .notFound)
    #expect(info.size() == 0)
  }
}
