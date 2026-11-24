#pragma once

#include <time.h>
#include <AudioToolbox/AUParameters.h>

namespace SF2::Utils {

struct Timer {
  /// @returns a monotonic clock value in nanoseconds. CLOCK_REALTIME (wall-clock time) is not used: NTP adjustments can
  /// move it forwards (a false render-budget overrun) or backwards (an unsigned `delta` that wraps around).
  static uint64_t now() noexcept { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
  /// @returns the elapsed time since given value
  static uint64_t delta(uint64_t then) noexcept { return now() - then; }
};

} // end namespace SF2::Utils
