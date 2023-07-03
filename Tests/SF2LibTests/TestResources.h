#import <Foundation/Foundation.h>

@interface TestResources : NSObject

+ (NSURL*)getResourceUrl:(int)index;
+ (NSURL*)getBadResourceUrl:(int)index;

@end
