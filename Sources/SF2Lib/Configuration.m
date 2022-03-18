// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Configuration.h"

@implementation Configuration

static Configuration* shared = NULL;
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
  shared = NULL;
  onceToken = NULL;
}

#if defined(SWIFTPM_MODULE_BUNDLE)

+ (NSString*)getConfigurationPath {
  @try {
    return [SWIFTPM_MODULE_BUNDLE pathForResource:@"Configuration" ofType:@"plist"];
  } @catch (NSException *exception) {
    NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
    for (int index = 0; index < [allBundles count]; ++index) {
      NSBundle* bundle = [allBundles objectAtIndex:index];
      NSString* bundleIdent = bundle.bundleIdentifier;
      NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
      NSString* found = [bundle pathForResource:@"Configuration" ofType:@"plist"];
      if (found != NULL) return found;
    }
    return NULL;
  }
}

#else

+ (NSString*)getConfigurationPath {
  NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
  for (int index = 0; index < [allBundles count]; ++index) {
    NSBundle* bundle = [allBundles objectAtIndex:index];
    NSString* bundleIdent = bundle.bundleIdentifier;
    NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
    NSString* found = [bundle pathForResource:@"Configuration" ofType:@"plist"];
    if (found != NULL) return found;
  }

  return NULL;
}

#endif

- (instancetype)init:(nullable NSDictionary*)overrides {
  if (self = [super init]) {
    NSString* path = [Configuration getConfigurationPath];
    NSMutableDictionary* config = [[NSMutableDictionary alloc] init];
    [config addEntriesFromDictionary:[NSDictionary dictionaryWithContentsOfFile:path]];
    if (overrides != NULL) {
      [config addEntriesFromDictionary:overrides];
    }
    _config = config;
    _loggingBase = _config[@"loggingBase"];
    NSNumber* tmp = _config[@"testsPlayAudio"];
    _testsPlayAudio = tmp != NULL && [tmp boolValue] == YES;
  }
  return self;
}

@end
