// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Util/Timer.hpp"

mach_timebase_info_data_t SF2::Utils::Timer::timebase_ = []() {
  mach_timebase_info_data_t value;
  mach_timebase_info(&value);
  return value;
}();
