#pragma once

#import <time.h>

#import <AudioToolbox/AUParameters.h>

namespace SF2::Utils {

struct Timer {
  /// @returns a clock value in nanoseconds
  inline static uint64_t now() noexcept { return clock_gettime_nsec_np(CLOCK_REALTIME); }
  /// @returns the elapsed time since given value
  inline static uint64_t delta(uint64_t then) noexcept { return now() - then; }
};

} // end namespace SF2::Utils
