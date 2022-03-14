// Copyright © 2021 Brad Howes. All rights reserved.
//

#import "TestResources.h"

@implementation TestResources : NSObject

#ifndef SWIFTPM_MODULE_BUNDLE

+ (NSArray<NSURL*>*)getSoundFontUrls {
  NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
  for (int index = 0; index < [allBundles count]; ++index) {
    NSBundle* bundle = [allBundles objectAtIndex:index];
    NSString* bundleIdent = bundle.bundleIdentifier;
    NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
    // if ([bundleIdent isEqualToString:@"SF2Lib-SF2LibTests"]) {
    NSArray<NSURL*>* found = [bundle URLsForResourcesWithExtension:@"sf2" subdirectory:nil];
    if (found != NULL && found.count == 3) {
      return found;
    }
  }

  return NULL;
}

#else

+ (NSArray<NSURL*>*)getSoundFontUrls {
  return [SWIFTPM_MODULE_BUNDLE URLsForResourcesWithExtension:@"sf2" subdirectory:nil];
}

#endif

+ (NSURL*)getResourceUrl:(int)urlIndex
{
  return [[TestResources getSoundFontUrls] objectAtIndex:urlIndex];
}

@end
