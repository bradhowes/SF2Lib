// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Configuration.h"

@implementation Configuration

static Configuration* shared = nullptr;
static dispatch_once_t onceToken;

+ (id)shared:(NSDictionary *)overrides {
  dispatch_once(&onceToken, ^{
    shared = [[Configuration alloc] init:overrides];
  });
  return shared;
}

+ (id)shared {
  dispatch_once(&onceToken, ^{
    shared = [[Configuration alloc] init:NULL];
  });
  return shared;
}

+ (void)reset {
  shared = nullptr;
  onceToken = {};
}

- (instancetype)init:(nullable NSDictionary*)overrides {
  if (self = [super init]) {
    NSString* path = [SWIFTPM_MODULE_BUNDLE pathForResource:@"Configuration" ofType:@"plist"];
    NSMutableDictionary* config = [[NSMutableDictionary alloc] init];
    [config addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:path]];
    if (overrides != nullptr) {
      [config addEntriesFromDictionary:overrides];
    }
    _config = config;
    _loggingBase = _config[@"loggingBase"];
    _testsPlayAudio = _config[@"testsPlayAudio"];
  }
  return self;
}

@end
