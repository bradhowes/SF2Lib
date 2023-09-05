// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/IO/Pos.hpp"
#include "SF2Lib/Entity/SampleHeader.hpp"
#include "SF2Lib/Utils/StringUtils.hpp"

using namespace SF2::Entity;

SampleHeader::SampleHeader(IO::Pos& pos) noexcept
{
  // Account for the extra padding by reading twice.
  pos = pos.readInto(&achSampleName, 40);
  pos = pos.readInto(&originalKey, 6);
  SF2::Utils::trim_property(achSampleName);
}

SampleHeader::SampleHeader(uint32_t start, uint32_t end, uint32_t loopBegin, uint32_t loopEnd,
                           uint32_t sampleRate, uint8_t key, int8_t adjustment, uint16_t link,
                           Type type) noexcept :
achSampleName{"blah"},
dwStart{start},
dwEnd{end},
dwStartLoop{loopBegin},
dwEndLoop{loopEnd},
dwSampleRate{sampleRate},
originalKey{key},
correction{adjustment},
sampleLink{link},
sampleType{SF2::valueOf(type)}
{}

std::string
SampleHeader::sampleTypeDescription() const noexcept
{
  std::string tag("");
  if (sampleIsA(Type::monoSample)) tag += "M";
  if (sampleIsA(Type::rightSample)) tag += "R";
  if (sampleIsA(Type::leftSample)) tag += "L";
  if (sampleIsA(Type::rom)) tag += "*";
  return tag;
}

void
SampleHeader::dump(const std::string& indent, size_t index) const noexcept
{
  std::cout << indent << '[' << index << "] '" << achSampleName
  << "' sampleRate: " << dwSampleRate
  << " S: " << dwStart << " E: " << dwEnd << " link: " << sampleLink
  << " SL: " << dwStartLoop << " EL: " << dwEndLoop
  << " type: " << sampleType << ' ' << sampleTypeDescription()
  << " originalKey: " << int(originalKey) << " correction: " << int(correction)
  << std::endl;
}
