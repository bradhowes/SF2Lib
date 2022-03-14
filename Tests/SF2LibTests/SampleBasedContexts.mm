// Copyright © 2021 Brad Howes. All rights reserved.
//

#import "SF2Lib/Configuration.h"

#include "SampleBasedContexts.hpp"
#include "TestResources.h"

using namespace SF2;
using namespace SF2::Render;

NSURL* PresetTestContextBase::getUrl(int urlIndex)
{
  return [TestResources getResourceUrl:urlIndex];
}

@implementation XCTestCase (SampleComparison)

@end
