#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "SF2Lib/Configuration.hpp"

@interface ConfigurationTests : XCTestCase

@end

@implementation ConfigurationTests

- (void)testNormal {
  [Configuration reset];
  XCTAssertEqualObjects(@"com.braysoftware.SF2Lib", Configuration.shared.loggingBase);
}

- (void)testOverrides {
  [Configuration reset];
  [Configuration shared:@{@"loggingBase":@"foo.bar.blah"}];
  XCTAssertEqualObjects(@"foo.bar.blah", Configuration.shared.loggingBase);
}

- (void)testReset {
  [Configuration reset];
  XCTAssertEqualObjects(@"com.braysoftware.SF2Lib", Configuration.shared.loggingBase);
  [Configuration reset];
  [Configuration shared:@{@"loggingBase":@"foo.bar.blah"}];
  XCTAssertEqualObjects(@"foo.bar.blah", Configuration.shared.loggingBase);
}

- (void)testPrimary {
  auto z = [Configuration getConfigurationPath];
  XCTAssertNotNil(z);
}

- (void)testAlternate {
  auto bundles = [NSBundle allBundles];
  for (int index = 0; index < bundles.count; ++index) {
    NSBundle* bundle = [bundles objectAtIndex:index];
    auto z = [Configuration getConfigurationPath: @"Configuration" from: bundle];
    XCTAssertNotNil(z);
    auto z2 = [Configuration getConfigurationPath: @"wfejefjweofijweofe f" from: bundle];
    XCTAssertNil(z2);
  }

  auto z = [Configuration getConfigurationPath: @"Blah" from: NULL];
  XCTAssertNil(z);
}

@end
