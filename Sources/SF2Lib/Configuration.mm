// Copyright © 2022 Brad Howes. All rights reserved.

#include "SF2Lib/Configuration.hpp"

@implementation Configuration

@synthesize config = _config;
@synthesize loggingBase = _loggingBase;
@synthesize testsPlayAudio = _testsPlayAudio;

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

+ (nullable NSString* )locate:(NSString*)name ofType:(NSString*)type {
  NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
  for (NSUInteger index = 0; index < [allBundles count]; ++index) {
    NSBundle* bundle = [allBundles objectAtIndex:index];
    NSString* bundleIdent = bundle.bundleIdentifier;
    NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
    NSString* found = [bundle pathForResource:@"SF2Lib_SF2Lib" ofType:@"bundle"];
    if (found != NULL) {
      bundle = [[NSBundle alloc] initWithPath:found];
      bundleIdent = bundle.bundleIdentifier;
      NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
      found = [bundle pathForResource:name ofType:@"plist"];
      if (found != NULL) return found;
    }
  }
  return NULL;
}

#if defined(SWIFTPM_MODULE_BUNDLE)

+ (nullable NSString*)getConfigurationPath:(NSString*)name from:(nullable NSBundle*)bundle {
  if (bundle) {
    NSString* found = [bundle pathForResource:name ofType:@"plist"];
    if (found) return found;
  }
  return [Configuration locate:name ofType:@"plist"];
}

+ (NSString*)getConfigurationPath {
  return [Configuration getConfigurationPath: @"Configuration" from: SWIFTPM_MODULE_BUNDLE];
}

#else

+ (nullable NSString*)getConfigurationPath {
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
  if ((self = [super init])) {
    NSString* path = [Configuration getConfigurationPath];
    NSMutableDictionary* config = [[NSMutableDictionary alloc] init];
    NSDictionary* fromFile = [NSDictionary dictionaryWithContentsOfFile:path];
    if (fromFile != nullptr) [config addEntriesFromDictionary:fromFile];
    if (overrides != nullptr) {
      NSDictionary* ors = overrides;
      [config addEntriesFromDictionary:ors];
    }
    _config = config;
    NSString* loggingBase = _config[@"loggingBase"];
    _loggingBase = loggingBase != nullptr ? loggingBase : @"???";
    NSNumber* tmp = _config[@"testsPlayAudio"];
    _testsPlayAudio = tmp != NULL && [tmp boolValue] == YES;
  }
  return self;
}

@end
