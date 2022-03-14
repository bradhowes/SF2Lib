// Copyright © 2021 Brad Howes. All rights reserved.
//

#import "TestResources.h"

@implementation TestResources : NSObject

+ (NSURL*)getResourceUrl:(int)urlIndex
{
//  NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
//  for (int index = 0; index < [allBundles count]; ++index) {
//    NSBundle* bundle = [allBundles objectAtIndex:index];
//    NSString* bundleIdent = bundle.bundleIdentifier;
//    NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
//    if ([bundleIdent isEqualToString:@"SF2Lib_SF2LibTests"]) {
//      NSArray<NSURL*>* urls = [bundle URLsForResourcesWithExtension:@"sf2" subdirectory:nil];
//      return [urls objectAtIndex:urlIndex];
//    }
//  }

//  NSLog(@"%@", [SWIFTPM_MODULE_BUNDLE description]);
  NSArray<NSURL*>* urls = [SWIFTPM_MODULE_BUNDLE URLsForResourcesWithExtension:@"sf2" subdirectory:nil];
//  NSLog(@"%@", urls);
  
  return [urls objectAtIndex:urlIndex];
}

@end
