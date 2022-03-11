// Copyright © 2022 Brad Howes. All rights reserved.

#import <Foundation/Foundation.h>

#include "SF2Lib/Configuration.h"
#include "SF2Lib/Logger.hpp"

const std::string SF2::Logger::base = []() {
  NSString* value = Configuration.shared.loggingBase;
  if (value == nullptr) value = @"com.braysoftware.SF2Lib";
  return std::string([value UTF8String]);
}();

SF2::Logger
SF2::Logger::Make(const std::string& subsystem, const std::string& category) noexcept {
  return SF2::Logger(os_log_create((base + subsystem).c_str(), category.c_str()));
}
