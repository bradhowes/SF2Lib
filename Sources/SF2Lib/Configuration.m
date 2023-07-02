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

+ (NSString*)getConfigurationPath:(NSString*)name from:(NSBundle*)bundle {
  @try {
    return [bundle pathForResource:name ofType:@"plist"];
  } @catch (NSException *exception) {
  }
  // Most likely we are in a unit test for something that depends on SF2Lib -- either the build system is not putting
  // stuff in the right location, or the code for SWIFTPM_MODULE_BUNDLE is not accounting for the test case.
  NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
  for (int index = 0; index < [allBundles count]; ++index) {
    NSBundle* bundle = [allBundles objectAtIndex:index];
    NSString* bundleIdent = bundle.bundleIdentifier;
    NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
    NSString* found = [bundle pathForResource:@"SF2Lib_SF2Lib" ofType:@"bundle"];
    if (found != NULL) {
      bundle = [[NSBundle alloc] initWithPath:found];
      bundleIdent = bundle.bundleIdentifier;
      NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
      NSString* found = [bundle pathForResource:name ofType:@"plist"];
      if (found != NULL) return found;
    }
  }
  return NULL;
}

+ (NSString*)getConfigurationPath {
  return [Configuration getConfigurationPath: @"Configuration"
                                        from: SWIFTPM_MODULE_BUNDLE];
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
