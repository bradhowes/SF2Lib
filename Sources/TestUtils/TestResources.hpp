#import <Foundation/Foundation.h>

#import "SF2File/IO/File.hpp"

@interface TestResources : NSObject

+ (NSArray<NSURL*>*)getInitSoundFontUrls;
+ (NSURL*)getResourceUrl:(NSUInteger)index;
+ (std::string)getResourcePath:(NSUInteger)index;
+ (NSURL*)getBadResourceUrl:(NSUInteger)index;
+ (SF2::IO::File&)getFile:(NSUInteger)index;

@end
