// Copyright © 2022 Brad Howes. All rights reserved.

#include <cmath>
#include <iostream>
#include <sstream>

#include "SF2Lib/Entity/Modulator/Source.hpp"

using namespace SF2::Entity::Modulator;

std::string
Source::description() const noexcept {
  std::ostringstream os;
  if (isGeneralController()) {
    switch (generalIndex()) {
      case GeneralIndex::none: os << "none"; break;
      case GeneralIndex::noteOnVelocity: os << "velocity"; break;
      case GeneralIndex::noteOnKey: os << "key"; break;
      case GeneralIndex::keyPressure: os << "keyPressure"; break;
      case GeneralIndex::channelPressure: os << "channelPressure"; break;
      case GeneralIndex::pitchWheel: os << "pitchWheel"; break;
      case GeneralIndex::pitchWheelSensitivity: os << "pitchWheelSensitivity"; break;
    }
  }
  else {
    os << "CC[" << ccIndex().value << ']';
  }

  os << '(' << (isUnipolar() ? "uni" : "bi") << '/' << (isPositive() ? "-+" : "+-") << '/'
  << continuityTypeName() << ')';

  return os.str();
}

namespace SF2::Entity::Modulator {

std::ostream&
operator<<(std::ostream& os, const Source& mod) noexcept
{
  return os << mod.description();
}

}
