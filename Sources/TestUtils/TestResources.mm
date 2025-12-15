// Copyright © 2021 Brad Howes. All rights reserved.
//

#import "TestResources.hpp"
#import "SF2File/IO/File.hpp"

#include <pthread.h>

// Setup internal state that is loaded once for all tests.
//
static pthread_once_t soundFontUrls_init_ = PTHREAD_ONCE_INIT;
static NSArray<NSURL*>* soundFontUrls_ = nullptr;
static NSPredicate* onlyGood = [NSPredicate predicateWithFormat: @"not absoluteString contains %@", @"ZZZ"];
static NSPredicate* onlyBad = [NSPredicate predicateWithFormat: @"absoluteString contains %@", @"ZZZ"];
static std::vector<SF2::IO::File> files_;

void initSoundFontUrls() {
  soundFontUrls_ = [TestResources getInitSoundFontUrls];
  files_.reserve(soundFontUrls_.count);
  for (size_t index = 0; index < soundFontUrls_.count; ++index) {
    auto url = [soundFontUrls_ objectAtIndex:index];
    NSLog(@"getSoundFontUrls[%lu] = %@", index, url);
    auto isBad = [url.absoluteString containsString:@"ZZZ"];
    if (!isBad) {
      files_.emplace_back(url.path.UTF8String);
      files_.back().load();
    }
  }
  NSLog(@"soundFontUrls: %lu files: %zu", soundFontUrls_.count, files_.size());
}

@implementation TestResources : NSObject

#ifndef SWIFTPM_MODULE_BUNDLE

+ (NSArray<NSURL*>*)getInitSoundFontUrls {
  pthread_once(&soundFontUrls_init_, initSoundFontUrls);
  NSArray<NSBundle*>* allBundles = [NSBundle allBundles];
  for (int index = 0; index < [allBundles count]; ++index) {
    NSBundle* bundle = [allBundles objectAtIndex:index];
    NSString* bundleIdent = bundle.bundleIdentifier;
    NSLog(@"bundle: %@ - %@", bundleIdent, bundle.resourcePath);
    NSArray<NSURL*>* found = [bundle URLsForResourcesWithExtension:@"sf2" subdirectory:nil];
    if (found != NULL && found.count == 3) {
      return found;
    }
  }

  return NULL;
}

#else


+ (NSArray<NSURL*>*)getInitSoundFontUrls {
  return [SWIFTPM_MODULE_BUNDLE URLsForResourcesWithExtension:@"sf2" subdirectory:nil];
}

#endif

+ (NSArray<NSURL*>*)getSoundFontUrls {
  pthread_once(&soundFontUrls_init_, initSoundFontUrls);
  return soundFontUrls_;
}

+ (NSURL*)getResourceUrl:(NSUInteger)urlIndex
{
  auto urls = [TestResources getSoundFontUrls];
  auto url = [[urls filteredArrayUsingPredicate:onlyGood] objectAtIndex:urlIndex];
  return url;
}

+ (NSURL*)getBadResourceUrl:(NSUInteger)urlIndex
{
  auto urls = [TestResources getSoundFontUrls];
  auto url = [[urls filteredArrayUsingPredicate:onlyBad] objectAtIndex:urlIndex];
  return url;
}

+ (SF2::IO::File&)getFile:(NSUInteger)index
{
  pthread_once(&soundFontUrls_init_, initSoundFontUrls);
  return files_[index];
}

@end
