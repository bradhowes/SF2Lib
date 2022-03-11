#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

#import "SF2Lib/Configuration.h"

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

@end
