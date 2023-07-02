// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Configuration : NSObject

@property (nonatomic, readonly) NSDictionary* config;
@property (nonatomic, readonly) NSString* loggingBase;
@property (nonatomic, readonly) BOOL testsPlayAudio;

+ (instancetype)shared:(NSDictionary*)overrides;
+ (instancetype)shared;
+ (void)reset;
+ (NSString*)getConfigurationPath;
+ (NSString*)getConfigurationPath:(NSString*)name from:(NSBundle*)bundle;

@end

NS_ASSUME_NONNULL_END
