// Copyright © 2022, 2025 Brad Howes. All rights reserved.

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
+ (nullable NSString*)getConfigurationPath;

#if defined(SWIFTPM_MODULE_BUNDLE)

+ (nullable NSString *)getConfigurationPath:(NSString *)name
                                       from:(nullable NSBundle *)bundle;

#else

+ (nullable NSString*)locate:(NSString*)name ofType:(NSString*)type;

#endif

@end

NS_ASSUME_NONNULL_END
