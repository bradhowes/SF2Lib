// Copyright © 2021 Brad Howes. All rights reserved.
//

#include "SampleBasedContexts.hpp"

using namespace SF2;
using namespace SF2::Render;

NSURL* PresetTestContextBase::getUrl(int urlIndex)
{
  //  NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
  //  for (int index = 0; index < [allBundles count]; ++index) {
  //    NSBundle* bundle = [allBundles objectAtIndex:index];
  //    NSLog(@"bundle: %@ - %@", bundle.bundleIdentifier, bundle.resourcePath);
  //  }

  NSBundle* bundle = [NSBundle bundleWithIdentifier:@"SF2LibTests"];
  NSLog(@"bundle: %@ - %@", bundle.bundleIdentifier, bundle.resourcePath);

  NSURL* sf2LibUrl = [bundle URLForResource:@"SF2Lib_SF2Lib" withExtension:@"bundle"];
  NSLog(@"sf2libUrl: %@", sf2LibUrl);

  NSBundle* sf2LibBundle = [NSBundle bundleWithURL:sf2LibUrl];
  NSLog(@"sf2LibBundle: %@", sf2LibBundle);

  NSArray<NSURL*>* urls = [sf2LibBundle URLsForResourcesWithExtension:@"sf2" subdirectory:nil];
  NSLog(@"%@", urls);

  return [urls objectAtIndex:urlIndex];
  
  NSURL* sf2Url = [sf2LibBundle URLForResource:@"FreeFont" withExtension:@"sf2"];
  NSLog(@"sf2Url: %@", sf2Url);
  if (urlIndex == 0) return sf2Url;

  sf2Url = [sf2LibBundle URLForResource:@"RolandNicePiano" withExtension:@"sf2"];
  NSLog(@"sf2Url: %@", sf2Url);
  return sf2Url;
}

@implementation XCTestCase (SampleComparison)

@end
