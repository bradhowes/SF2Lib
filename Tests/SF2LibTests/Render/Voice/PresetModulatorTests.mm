// Copyright © 2026 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

using namespace SF2;
using Mod = SF2Builder::Mod;
using LoadResponse = SF2::IO::File::LoadResponse;

// Modulator sources (SF2.01 8.2): CC flag 0x80, D (negative) bit 0x100, concave type 0x400.
static constexpr uint16_t cc16 = 0x0080 | 16;                  // CC 16, positive unipolar linear
static constexpr uint16_t cc17 = 0x0080 | 17;                  // CC 17, positive unipolar linear
static constexpr uint16_t velocityNegConcave = 0x0502;         // the default velocity -> attenuation source (8.4.1)
static constexpr uint16_t noController = 0;                    // "No Controller" (8.2.1)
static constexpr uint16_t attenuation = 48;                    // initialAttenuation

static const Mod terminal{0, 0, 0, 0, 0};

/// Set the modulators of the minimal file's instrument zone
static void setInstrumentMods(SF2Builder& builder, std::vector<Mod> mods)
{
  builder.ibag[1].modulatorIndex = uint16_t(mods.size());
  mods.push_back(terminal);
  builder.imod = mods;
}

/// Set the modulators of the minimal file's preset zone, optionally with a global preset zone in front of it
static void setPresetMods(SF2Builder& builder, std::vector<Mod> local, std::vector<Mod> global = {})
{
  if (global.empty()) {
    builder.pbag = {{0, 0}, {1, uint16_t(local.size())}};
    builder.phdr[1].bagIndex = 1;
  } else {
    // Zone 0 has modulators but no generators, so it is the global zone. Zone 1 links to the instrument.
    builder.pbag = {{0, 0}, {0, uint16_t(global.size())}, {1, uint16_t(global.size() + local.size())}};
    builder.phdr[1].bagIndex = 2;
  }
  std::vector<Mod> mods{global};
  mods.insert(mods.end(), local.begin(), local.end());
  mods.push_back(terminal);
  builder.pmod = mods;
}

/// Render 0.1 s of key 69 after setting CC 16 and CC 17 to 100. Returns the left channel of the dry bus.
static std::vector<AUValue> render(const SF2Builder& builder, uint8_t velocity = 127)
{
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibPresetMods.sf2";
  builder.writeTo(path);
  auto harness{TestEngineHarness{48000.0}};
  if (harness.load(path, 0) != LoadResponse::ok) return {};
  auto mixer{harness.createMixer(0.1)};
  harness.sendRaw(std::array<uint8_t, 3>{0xB0, 16, 100});
  harness.sendRaw(std::array<uint8_t, 3>{0xB0, 17, 100});
  harness.sendNoteOn(69, velocity);
  harness.renderToEnd(mixer);
  const AUValue* data = harness.dryBuffer().floatChannelData[0];
  return std::vector<AUValue>(data, data + harness.duration());
}

@interface PresetModulatorTests : XCTestCase
@end

@implementation PresetModulatorTests

- (void)testPresetModulatorAddsToIdenticalInstrumentModulator {
  // 9.5.1: "A modulator at the preset level adds to a modulator at the instrument level if both modulators are
  // identical." Instrument 200 + preset 100 must sound like instrument 300. Previously PMOD was ignored.
  auto summed = SF2Builder::minimal();
  setInstrumentMods(summed, {{cc16, attenuation, 300, 0, 0}});
  auto split = SF2Builder::minimal();
  setInstrumentMods(split, {{cc16, attenuation, 200, 0, 0}});
  auto instrumentOnly = split;
  setPresetMods(split, {{cc16, attenuation, 100, 0, 0}});

  auto expected = render(summed);
  XCTAssertFalse(expected.empty());
  XCTAssertTrue(render(split) == expected);
  XCTAssertFalse(render(instrumentOnly) == expected);
}

- (void)testPresetModulatorWithoutMatchIsAdded {
  // 9.5.1: "Otherwise, the effects of a modulator at the preset level are added".
  auto instrument = SF2Builder::minimal();
  setInstrumentMods(instrument, {{cc16, attenuation, 300, 0, 0}});
  auto preset = SF2Builder::minimal();
  setPresetMods(preset, {{cc16, attenuation, 300, 0, 0}});

  auto expected = render(instrument);
  XCTAssertTrue(render(preset) == expected);
  XCTAssertFalse(render(SF2Builder::minimal()) == expected);
}

- (void)testPresetModulatorAddsToDefaultModulator {
  // 9.5.1: a preset modulator identical to a default modulator adds to it. The default velocity -> attenuation
  // modulator has amount 960, so a preset amount of -960 cancels it, just like an instrument modulator of 0 replacing it.
  auto replaced = SF2Builder::minimal();
  setInstrumentMods(replaced, {{velocityNegConcave, attenuation, 0, 0, 0}});
  auto cancelled = SF2Builder::minimal();
  setPresetMods(cancelled, {{velocityNegConcave, attenuation, -960, 0, 0}});

  auto expected = render(replaced, 64);
  XCTAssertTrue(render(cancelled, 64) == expected);
  XCTAssertFalse(render(SF2Builder::minimal(), 64) == expected);
}

- (void)testLocalPresetModulatorSupersedesGlobal {
  // 9.5.1: "A modulator, contained within a local preset zone, that is identical to a modulator in a global preset
  // zone supersedes or replaces that modulator in the global preset zone."
  auto both = SF2Builder::minimal();
  setPresetMods(both, {{cc16, attenuation, 100, 0, 0}}, {{cc16, attenuation, 500, 0, 0}});
  auto localOnly = SF2Builder::minimal();
  setPresetMods(localOnly, {{cc16, attenuation, 100, 0, 0}});
  auto summed = SF2Builder::minimal();
  setPresetMods(summed, {{cc16, attenuation, 600, 0, 0}});

  auto expected = render(localOnly);
  XCTAssertTrue(render(both) == expected);
  XCTAssertFalse(render(summed) == expected);
}

- (void)testGlobalPresetModulatorIsAddedWhenNotSuperseded {
  // 9.5.1: a global preset zone modulator that is not superseded by the local zone has its effect added.
  auto preset = SF2Builder::minimal();
  setPresetMods(preset, {{cc16, attenuation, 100, 0, 0}}, {{cc17, attenuation, 200, 0, 0}});
  auto instrument = SF2Builder::minimal();
  setInstrumentMods(instrument, {{cc17, attenuation, 200, 0, 0}, {cc16, attenuation, 100, 0, 0}});
  auto localOnly = SF2Builder::minimal();
  setPresetMods(localOnly, {{cc16, attenuation, 100, 0, 0}});

  auto expected = render(instrument);
  XCTAssertTrue(render(preset) == expected);
  XCTAssertFalse(render(localOnly) == expected);
}

- (void)testDuplicatePresetModulatorLastWins {
  // 7.4: "If a second modulator is encountered with the same three enumerators as a previous modulator with the same
  // zone, the first modulator will be ignored."
  auto duplicated = SF2Builder::minimal();
  setPresetMods(duplicated, {{cc16, attenuation, 500, 0, 0}, {cc16, attenuation, 100, 0, 0}});
  auto single = SF2Builder::minimal();
  setPresetMods(single, {{cc16, attenuation, 100, 0, 0}});
  XCTAssertTrue(render(duplicated) == render(single));
  // Guard against a vacuous test: the preset modulator does have an effect.
  XCTAssertFalse(render(single) == render(SF2Builder::minimal()));
}

- (void)testNoControllerSourceActsAsOne {
  // 8.2.1: "No Controller ... should be treated as if its value were set to '1'. It should not be a means to turn off
  // a modulator." So a modulator with no source and amount 200 adds a constant 200 cB, like the generator itself.
  // Previously such a modulator did nothing.
  auto modulator = SF2Builder::minimal();
  setInstrumentMods(modulator, {{noController, attenuation, 200, 0, 0}});
  auto generator = SF2Builder::minimal();
  generator.igen.insert(generator.igen.begin(), {attenuation, 200});
  generator.ibag[1].generatorIndex += 1;

  auto expected = render(generator);
  XCTAssertTrue(render(modulator) == expected);
  XCTAssertFalse(render(SF2Builder::minimal()) == expected);

  // The same applies at the preset level.
  auto preset = SF2Builder::minimal();
  setPresetMods(preset, {{noController, attenuation, 200, 0, 0}});
  XCTAssertTrue(render(preset) == expected);
}

- (void)testReservedSourcesAreIgnored {
  // 8.2.1: reserved general sources (including 127, a 2.04 link) and illegal CCs (98-101) mean the whole modulator is
  // ignored. They use the negative direction so that a source value of 0 would give full effect if they were used.
  const uint16_t negative = 0x0100;
  auto reserved = SF2Builder::minimal();
  setInstrumentMods(reserved, {
    {uint16_t(127 | negative), attenuation, 960, 0, 0},
    {uint16_t(1 | negative), attenuation, 960, 0, 0},
    {uint16_t(0x0080 | 99 | negative), attenuation, 960, 0, 0},
    {uint16_t(0x0080 | 100 | negative), attenuation, 960, 0, 0},
    {cc16, attenuation, 960, uint16_t(127 | negative), 0}});
  setPresetMods(reserved, {{uint16_t(127 | negative), attenuation, 960, 0, 0}});

  auto expected = render(SF2Builder::minimal());
  XCTAssertTrue(render(reserved) == expected);

  // Guard against a vacuous test: the same modulator with a valid negative CC source does attenuate.
  auto valid = SF2Builder::minimal();
  setInstrumentMods(valid, {{uint16_t(0x0080 | 18 | negative), attenuation, 960, 0, 0}});
  XCTAssertFalse(render(valid) == expected);
}

@end
