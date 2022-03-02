// Copyright © 2021 Brad Howes. All rights reserved.
//

#include "SampleBasedContexts.hpp"

using namespace SF2;
using namespace SF2::Render;

NSURL* PresetTestContextBase::getUrl(int urlIndex)
{
    NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
    for (int index = 0; index < [allBundles count]; ++index) {
      NSBundle* bundle = [allBundles objectAtIndex:index];
      NSLog(@"bundle: %@ - %@", bundle.bundleIdentifier, bundle.resourcePath);
    }

  NSLog(@"%@", [SWIFTPM_MODULE_BUNDLE description]);
  NSArray<NSURL*>* urls = [SWIFTPM_MODULE_BUNDLE URLsForResourcesWithExtension:@"sf2" subdirectory:nil];
  NSLog(@"%@", urls);
  return [urls objectAtIndex:urlIndex];
}

@implementation XCTestCase (SampleComparison)

@end
