// Copyright © 2022 Brad Howes. All rights reserved.

#include <iostream>

#include "SF2Lib/Entity/SampleHeader.hpp"

using namespace SF2::Entity;

std::string
SampleHeader::sampleTypeDescription() const
{
  std::string tag("");
  if (sampleIsA(Type::monoSample)) tag += "M";
  if (sampleIsA(Type::rightSample)) tag += "R";
  if (sampleIsA(Type::leftSample)) tag += "L";
  if (sampleIsA(Type::rom)) tag += "*";
  return tag;
}

void
SampleHeader::dump(const std::string& indent, size_t index) const
{
  std::cout << indent << '[' << index << "] '" << achSampleName
  << "' sampleRate: " << dwSampleRate
  << " S: " << dwStart << " E: " << dwEnd << " link: " << sampleLink
  << " SL: " << dwStartLoop << " EL: " << dwEndLoop
  << " type: " << sampleType << ' ' << sampleTypeDescription()
  << " originalKey: " << int(originalKey) << " correction: " << int(correction)
  << std::endl;
}
