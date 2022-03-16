//// Copyright © 2022 Brad Howes. All rights reserved.
//
//#include "SF2Lib/ConstMath.hpp"
//#include "SF2Lib/Types.hpp"
//#include "SF2Lib/DSP/DSP.hpp"
//
//using namespace SF2;
//using namespace SF2::DSP;
//
//static constexpr size_t TableSize = 1441;
//
//static constexpr double value(size_t index) {
//  return 6.875 * ConstMath::exp(index / 1200.0 * ConstMath::constants<double>::ln2);
//}
//
//static constexpr auto lookup_ = ConstMath::make_array<double, TableSize>(value);
//
///**
// Convert a value between 0 and 1200 into a frequency multiplier. See DSP::centsToFrequency for details on how it is
// used.
//
// @param partial a value between 0 and MaxCentsValue - 1
// @returns frequency multiplier
// */
//double
//SF2::DSP::attenuationLookup(int centibels) noexcept {
//  return lookup_[size_t(std::clamp<int>(centibels, 0, TableSize - 1))];
//}
