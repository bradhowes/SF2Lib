#pragma once

#import <mach/mach.h>
#import <mach/mach_time.h>
#import <AudioToolbox/AUParameters.h>

namespace SF2::Utils {

struct Timer {

  inline static uint64_t now() noexcept { return mach_absolute_time(); }
  inline static uint64_t delta(uint64_t then) noexcept { return now() - then; }

  inline static AUValue milliseconds(uint64_t delta) noexcept {
    delta *= timebase_.numer;
    delta /= timebase_.denom;
    return AUValue(delta / 1000000); // convert from nanoseconds to milliseconds
  }

private:
  static mach_timebase_info_data_t timebase_;
};

} // end namespace SF2::Utils
