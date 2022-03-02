//
//  Logger.cpp.cpp
//  
//
//  Created by Brad Howes on 02/03/2022.
//

#include "Logger.hpp"

const std::string SF2::Logger::base{"SF2Lib"};

SF2::Logger
SF2::Logger::Make(const std::string& subsystem, const std::string& category) {
  return SF2::Logger(os_log_create((base + subsystem).c_str(), category.c_str()));
}
