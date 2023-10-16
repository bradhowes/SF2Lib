#import <Foundation/Foundation.h>
#import <SF2Lib/IO/File.hpp>

@interface TestResources : NSObject

+ (NSArray<NSURL*>*)getInitSoundFontUrls;
+ (NSURL*)getResourceUrl:(int)index;
+ (NSURL*)getBadResourceUrl:(int)index;
+ (SF2::IO::File&)getFile:(int)index;

@end
