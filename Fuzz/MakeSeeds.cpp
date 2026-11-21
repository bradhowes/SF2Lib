// Copyright © 2026 Brad Howes. All rights reserved.
//
// Writes a small seed corpus for SF2FileFuzzer into the directory given on the command line. The large SF2 files in
// Sources/TestUtils/Resources are far too big to make useful seeds.

#include <iostream>
#include <string>

#include "SF2Builder.hpp"

int main(int argc, char** argv)
{
  if (argc != 2) {
    std::cerr << "usage: " << argv[0] << " CORPUS_DIR\n";
    return 1;
  }
  std::string dir{argv[1]};
  bool ok = true;

  auto minimal = SF2Builder::minimal();
  ok &= minimal.writeTo(dir + "/minimal.sf2");

  // Instrument zone with key/velocity ranges, extra generators and modulators, plus a global zone.
  auto rich = SF2Builder::minimal();
  rich.igen = {
    {43, uint16_t(0 | (127 << 8))},  // keyRange 0-127
    {44, uint16_t(1 | (127 << 8))},  // velRange 1-127
    {8, 9'000},                      // initialFilterFc
    {9, 100},                        // initialFilterQ
    {0, 10},                         // startAddrsOffset
    {54, 1},                         // sampleModes
    {53, 0},                         // sampleID
    {0, 0}};
  rich.imod = {
    {0x0081, 8, -2'400, 0, 0},       // CC1 -> initialFilterFc
    {0x0502, 48, 960, 0, 0},         // velocity -> initialAttenuation
    {0, 0, 0, 0, 0}};
  rich.ibag = {{0, 0}, {7, 2}};
  rich.pgen = {{48, 30}, {41, 0}, {0, 0}};
  rich.pbag = {{0, 0}, {2, 0}};
  ok &= rich.writeTo(dir + "/rich.sf2");

  // Two presets sharing the instrument, the first with a global zone.
  auto twoPresets = SF2Builder::minimal();
  twoPresets.pgen = {{48, 10}, {41, 0}, {41, 0}, {0, 0}};
  twoPresets.pbag = {{0, 0}, {1, 0}, {2, 0}, {3, 0}};
  twoPresets.phdr = {{"Global", 0, 0, 0}, {"Second", 1, 0, 2}, {"EOP", 0, 0, 3}};
  ok &= twoPresets.writeTo(dir + "/two-presets.sf2");

  if (!ok) {
    std::cerr << "failed to write seeds to " << dir << '\n';
    return 1;
  }
  return 0;
}
