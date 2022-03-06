// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Logger.hpp"

const std::string SF2::Logger::base{"SF2Lib"};

SF2::Logger
SF2::Logger::Make(const std::string& subsystem, const std::string& category) {
  return SF2::Logger(os_log_create((base + subsystem).c_str(), category.c_str()));
}
