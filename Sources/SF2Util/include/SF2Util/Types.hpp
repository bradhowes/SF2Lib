// Copyright © 2022, 2025 Brad Howes. All rights reserved.

#pragma once

#include <os/log.h>

#include <AudioToolbox/AUParameters.h>
#include <cmath>
#include <concepts>
#include <type_traits>
#include <vector>

#import "DSPHeaders/Types.hpp"

namespace SF2 {

using namespace DSPHeaders;

/**
 Type to use for all floating-point operations in SF2. For precision we do everything in 64-bit and convert at AUValue
 (32-bit float) only when necessary.
 */
using Float = double;
using SampleVector = std::vector<Float>;

#ifndef __AVAudioTypes_h__
using AUValue = float;
using AUAudioFrameCount = uint32_t;
#else
using AUValue = ::AUValue;
using AUAudioFrameCount = ::AUAudioFrameCount;
#endif

struct Log {
  inline static const char* subsystem = "com.braysoftware.SF2Lib";

  inline static os_log_t create(const char* category) { return os_log_create(subsystem, category); }
};

} // end namespace SF2
