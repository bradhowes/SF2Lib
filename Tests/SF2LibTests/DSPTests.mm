// Copyright © 2021 Brad Howes. All rights reserved.

#include <XCTest/XCTest.h>
#include <cmath>
#include <iostream>
#include <iomanip>

#include "SampleBasedContexts.hpp"
#include "DSPHeaders/ConstMath.hpp"
#include "DSPHeaders/DSP.hpp"
#include "SF2Lib/DSP.hpp"

using namespace DSPHeaders::DSP;
using namespace SF2;
using namespace SF2::DSP;

@interface DSPTests : XCTestCase {
  SF2::Float epsilon;
}
@end

@implementation DSPTests

- (void)setUp {
  epsilon = PresetTestContextBase::epsilonValue();
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testClampFilterCutoff {
  XCTAssertEqual(1500, clampFilterCutoff(0));
  XCTAssertEqual(20000, clampFilterCutoff(22000));
  XCTAssertEqual(3000, clampFilterCutoff(3000));
  XCTAssertEqual(14000, clampFilterCutoff(14000));
}

- (void)testUnipolarModulation {
  XCTAssertEqual(unipolarModulation(-3.0, 10.0, 20.0), 10.0);
  XCTAssertEqual(unipolarModulation(0.0, 10.0, 20.0), 10.0);
  XCTAssertEqual(unipolarModulation(0.5, 10.0, 20.0), 15.0);
  XCTAssertEqual(unipolarModulation(1.0, 10.0, 20.0), 20.0);
  XCTAssertEqual(unipolarModulation(11.0, 10.0, 20.0), 20.0);
}

- (void)testBipolarModulation {
  XCTAssertEqual(bipolarModulation(-3.0, 10.0, 20.0), 10.0);
  XCTAssertEqual(bipolarModulation(-1.0, 10.0, 20.0), 10.0);
  XCTAssertEqual(bipolarModulation(0.0, 10.0, 20.0), 15.0);
  XCTAssertEqual(bipolarModulation(1.0, 10.0, 20.0), 20.0);
  XCTAssertEqual(bipolarModulation(-1.0, -20.0, 13.0), -20.0);
  XCTAssertEqual(bipolarModulation(0.0,  -20.0, 13.0), -3.5);
  XCTAssertEqual(bipolarModulation(1.0,  -20.0, 13.0), 13.0);
}

- (void)testUnipolarToBipolar {
  XCTAssertEqual(unipolarToBipolar(0.0), -1.0);
  XCTAssertEqual(unipolarToBipolar(0.5), 0.0);
  XCTAssertEqual(unipolarToBipolar(1.0), 1.0);
}

- (void)testBipolarToUnipolar {
  XCTAssertEqual(bipolarToUnipolar(-1.0), 0.0);
  XCTAssertEqual(bipolarToUnipolar(0.0), 0.5);
  XCTAssertEqual(bipolarToUnipolar(1.0), 1.0);
}

- (void)testPanLookup {
  SF2::Float left, right;
  //std::cout << std::setprecision(18) << centsPartialLookup(1199) << '\n';

  SF2::DSP::panLookup(-501, left, right);
  XCTAssertEqualWithAccuracy(1.0, left, epsilon);
  XCTAssertEqualWithAccuracy(0.0, right, epsilon);
  
  SF2::DSP::panLookup(-500, left, right);
  XCTAssertEqualWithAccuracy(1.0, left, epsilon);
  XCTAssertEqualWithAccuracy(0.0, right, epsilon);
  
  SF2::DSP::panLookup(-100, left, right);
  std::cout << std::setprecision(18) << left << '\n';
  XCTAssertEqualWithAccuracy(0.809016994375, left, epsilon);
  XCTAssertEqualWithAccuracy(0.587785252292, right, epsilon);
  
  SF2::DSP::panLookup(0, left, right);
  XCTAssertEqualWithAccuracy(left, right, epsilon);
  std::cout << std::setprecision(18) << right << '\n';
  XCTAssertEqualWithAccuracy(0.707106781187, right, epsilon);

  SF2::DSP::panLookup(100, left, right);
  XCTAssertEqualWithAccuracy(0.587785252292, left, epsilon);
  std::cout << std::setprecision(18) << right << '\n';
  XCTAssertEqualWithAccuracy(0.809016994375, right, epsilon);
  
  SF2::DSP::panLookup(500, left, right);
  XCTAssertEqualWithAccuracy(0.0, left, epsilon);
  XCTAssertEqualWithAccuracy(1.0, right, epsilon);
  
  SF2::DSP::panLookup(501, left, right);
  XCTAssertEqualWithAccuracy(0.0, left, epsilon);
  XCTAssertEqualWithAccuracy(1.0, right, epsilon);
}

- (void)testCentsPartialLookup {
  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(6.875, centsPartialLookup(0), epsilon);
    XCTAssertEqualWithAccuracy(9.722718241315, centsPartialLookup(600), epsilon);
    XCTAssertEqualWithAccuracy(13.742059989514, centsPartialLookup(1199), epsilon);
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(6.875, centsPartialLookup(0), epsilon);
    XCTAssertEqualWithAccuracy(9.722718241315, centsPartialLookup(600), epsilon);
    //std::cout << std::setprecision(18) << centsPartialLookup(1199) << '\n';
    XCTAssertEqualWithAccuracy(13.7420599819439833, centsPartialLookup(1199), epsilon);
  }
}


- (void)testParabolicSineAccuracy {
  for (int index = 0; index < 36000.0; ++index) {
    auto theta = 2.0 * M_PI * index / 36000.0 - M_PI;
    auto real = std::sin(theta);
    XCTAssertEqualWithAccuracy(DSPHeaders::DSP::parabolicSine(theta), real, 0.0011);
  }
}

- (void)testCentToFrequency {
  if constexpr (std::is_same_v<Float, float>) {
    XCTAssertEqualWithAccuracy(1.0, centsToFrequency(-1), epsilon); // A0
    XCTAssertEqualWithAccuracy(8.1757989156437, centsToFrequency(0), epsilon); // A0
    XCTAssertEqualWithAccuracy(55.0, centsToFrequency(3300), epsilon); // A1
    XCTAssertEqualWithAccuracy(110.0, centsToFrequency(4500), epsilon); // A2
    XCTAssertEqualWithAccuracy(220.0, centsToFrequency(5700), epsilon); // A3
    // std::cout << std::setprecision(18) << centsToFrequency(6400) << '\n';
    XCTAssertEqualWithAccuracy(329.6275634765625, centsToFrequency(6400), epsilon); // C4
    XCTAssertEqualWithAccuracy(440.0, centsToFrequency(6900), epsilon); // A4
    XCTAssertEqualWithAccuracy(880.0, centsToFrequency(8100), epsilon); // A5
    XCTAssertEqualWithAccuracy(1760.0, centsToFrequency(9300), epsilon); // A6
    XCTAssertEqualWithAccuracy(3520.0, centsToFrequency(10500), epsilon); // A7
    // std::cout << std::setprecision(18) << centsToFrequency(10800) << '\n';
    XCTAssertEqualWithAccuracy(4186.0087890625, centsToFrequency(10800), epsilon); // C8
  } else if constexpr (std::is_same_v<Float, double>) {
    XCTAssertEqualWithAccuracy(1.0, centsToFrequency(-1), epsilon); // A0
    XCTAssertEqualWithAccuracy(8.1757989156437, centsToFrequency(0), epsilon); // A0
    XCTAssertEqualWithAccuracy(55.0, centsToFrequency(3300), epsilon); // A1
    XCTAssertEqualWithAccuracy(110.0, centsToFrequency(4500), epsilon); // A2
    XCTAssertEqualWithAccuracy(220.0, centsToFrequency(5700), epsilon); // A3
    XCTAssertEqualWithAccuracy(329.62755691286992, centsToFrequency(6400), epsilon); // C4
    XCTAssertEqualWithAccuracy(440.0, centsToFrequency(6900), epsilon); // A4
    XCTAssertEqualWithAccuracy(880.0, centsToFrequency(8100), epsilon); // A5
    XCTAssertEqualWithAccuracy(1760.0, centsToFrequency(9300), epsilon); // A6
    XCTAssertEqualWithAccuracy(3520.0, centsToFrequency(10500), epsilon); // A7
    XCTAssertEqualWithAccuracy(4186.009044809578, centsToFrequency(10800), epsilon); // C8
 }
}

- (void)testCentibelsToAttenuationLookup {
  XCTAssertEqualWithAccuracy(1.0, centibelsToAttenuation(-1), epsilon);
  XCTAssertEqualWithAccuracy(1.0, centibelsToAttenuation(0), epsilon);
  XCTAssertEqualWithAccuracy(0.891250938134, centibelsToAttenuation(10), epsilon);
  XCTAssertEqualWithAccuracy(0.881048873008, centibelsToAttenuation(11), epsilon);
  XCTAssertEqualWithAccuracy(0.316227766017, centibelsToAttenuation(100), epsilon);
  XCTAssertEqualWithAccuracy(1e-05, centibelsToAttenuation(1000), epsilon);
  XCTAssertEqualWithAccuracy(0.0, centibelsToAttenuation(1440), epsilon);
  XCTAssertEqualWithAccuracy(0.0, centibelsToAttenuation(1441), epsilon);
}

- (void)testAttenuationLookup {
  XCTAssertEqualWithAccuracy(1.0, DSP::AttenuationLookup::query(0), epsilon);
  XCTAssertEqualWithAccuracy(6.3095734448e-08, DSP::AttenuationLookup::query(MaximumAttenuationCentiBels), epsilon);
}

- (void)testCentibelsToAttenuattionInterpolated {
  XCTAssertEqualWithAccuracy(1.0, centibelsToAttenuationInterpolated(-1.0), epsilon);
  XCTAssertEqualWithAccuracy(1.0, centibelsToAttenuationInterpolated(0.0), epsilon);
  XCTAssertEqualWithAccuracy(0.891250938134, centibelsToAttenuationInterpolated(10.0), epsilon);
  XCTAssertEqualWithAccuracy(0.886149905571, centibelsToAttenuationInterpolated(10.5), epsilon);
  XCTAssertEqualWithAccuracy(0.881048873008, centibelsToAttenuationInterpolated(11.0), epsilon);
  XCTAssertEqualWithAccuracy(0.316227766017, centibelsToAttenuationInterpolated(100.0), epsilon);
  XCTAssertEqualWithAccuracy(1e-05, centibelsToAttenuationInterpolated(1000.0), epsilon);
  XCTAssertEqualWithAccuracy(0.0, centibelsToAttenuationInterpolated(1440.0), epsilon);
  XCTAssertEqualWithAccuracy(0.0, centibelsToAttenuationInterpolated(1441.0), epsilon);
}

- (void)testTenthPercentage {
  XCTAssertEqualWithAccuracy(0.0, SF2::DSP::tenthPercentageToNormalized(-1), 0.0001);
  XCTAssertEqualWithAccuracy(0.0, SF2::DSP::tenthPercentageToNormalized(0), 0.0001);
  XCTAssertEqualWithAccuracy(0.123, SF2::DSP::tenthPercentageToNormalized(123), 0.0001);
  XCTAssertEqualWithAccuracy(1.0, SF2::DSP::tenthPercentageToNormalized(1000), 0.0001);
  XCTAssertEqualWithAccuracy(1.0, SF2::DSP::tenthPercentageToNormalized(1001), 0.0001);
}

- (void)testLFOCentsToFrequency {
  XCTAssertEqualWithAccuracy(0.000792, SF2::DSP::lfoCentsToFrequency(-32768), 0.000001);
  XCTAssertEqualWithAccuracy(0.000792, SF2::DSP::lfoCentsToFrequency(-16000), 0.000001);
  XCTAssertEqualWithAccuracy(8.175799, SF2::DSP::lfoCentsToFrequency(0), 0.00001);
  XCTAssertEqualWithAccuracy(110.0, SF2::DSP::lfoCentsToFrequency(4500), 0.00001);
  XCTAssertEqualWithAccuracy(110.0, SF2::DSP::lfoCentsToFrequency(9000), 0.00001);
}

// Copied with small modifications from FluidSynth.
static Float fluid_iir_filter_q_from_dB(Float q_dB)
{
  /* The generator contains 'centibels' (1/10 dB) => divide by 10 to
   * obtain dB */
  q_dB /= 10.0;

  /* Range: SF2.01 section 8.1.3 # 8 (convert from cB to dB => /10) */
  q_dB = std::min<Float>(std::max<Float>(q_dB, 0.0), 96.0);

  /* Short version: Modify the Q definition in a way, that a Q of 0
   * dB leads to no resonance hump in the freq. response.
   *
   * Long version: From SF2.01, page 39, item 9 (initialFilterQ):
   * "The gain at the cutoff frequency may be less than zero when
   * zero is specified".  Assume q_dB=0 / q_lin=1: If we would leave
   * q as it is, then this results in a 3 dB hump slightly below
   * fc. At fc, the gain is exactly the DC gain (0 dB).  What is
   * (probably) meant here is that the filter does not show a
   * resonance hump for q_dB=0. In this case, the corresponding
   * q_lin is 1/sqrt(2)=0.707.  The filter should have 3 dB of
   * attenuation at fc now.  In this case Q_dB is the height of the
   * resonance peak not over the DC gain, but over the frequency
   * response of a non-resonant filter.  This idea is implemented as
   * follows: */
  q_dB -= 3.01;

  /* The 'sound font' Q is defined in dB. The filter needs a linear
   q. Convert. */
  q_dB /= 20.0;
  return std::pow(10.0, q_dB);
}

- (void)testCentiBelsToResonance {
  Float epsilon = []() {
    if constexpr (std::is_same_v<Float, float>) return 1.0e-1;
    if constexpr (std::is_same_v<Float, double>) return 1.0e-10;
  }();

  for (auto centibels = 0; centibels < 960; ++centibels) {
    auto fs = fluid_iir_filter_q_from_dB(centibels);
    auto us = DSP::centibelsToResonance(centibels);
    
    XCTAssertEqualWithAccuracy(fs, us, epsilon);
  }
}
@end
