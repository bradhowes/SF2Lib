// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <cassert>
#include <cmath>

#include "SF2Lib/Types.hpp"

namespace SF2::Utils {

/**
 Pairing of L+R audio buffers that are always worked on together.
 */
class OutputBufferPair
{
public:

  /**
   Construct a pair of empty buffers which never accumulate any values.
   */
  OutputBufferPair() = default;

  /**
   Treat the given value pointers as a pair of L+R output buffers that can hold `frameCount` samples. Zeros out the
   buffers so that they may be added into.

   @param left pointer to first location to store a sample for the left output channel
   @param right pointer to first location to store a sample for the right output channel
   @param maxFrameCount maximum number of samples to process
   */
  OutputBufferPair(SF2::AUValue* left, SF2::AUValue* right, SF2::AUAudioFrameCount maxFrameCount)
  : left_{left}, right_{right}
  {
    assert(left != nullptr && right != nullptr);

#if 1
    vDSP_vclr(left_, 1, maxFrameCount);
    vDSP_vclr(right_, 1, maxFrameCount);
#else
    std::fill(left_, left_ + maxFrameCount, 0.0);
    std::fill(right_, right_ + maxFrameCount, 0.0);
#endif
  }

  void add(const SF2::AUValue* samples, SF2::AUAudioFrameCount frameCount,
           SF2::AUValue leftGain, SF2::AUValue rightGain)
  {
    if (left_ == nullptr) return;

#if 1
    // left_ += samples * leftGain
    vDSP_vsma(samples, 1, &leftGain, left_, 1, left_, 1, frameCount);
    // right_ += samples * rightGain
    vDSP_vsma(samples, 1, &rightGain, right_, 1, right_, 1, frameCount);
#else
    if (leftGain > 0.0) {
      if (rightGain > 0.0) {
        for (auto index = 0; index < frameCount; ++index) {
          left_[index] += samples[index] * leftGain;
          right_[index] += samples[index] * rightGain;
        }
      } else {
        for (auto index = 0; index < frameCount; ++index) {
          left_[index] += samples[index] * leftGain;
        }
      }
    } else if (rightGain > 0.0) {
      for (auto index = 0; index < frameCount; ++index) {
        right_[index] += samples[index] * rightGain;
      }
    }
#endif
  }

  void shift(SF2::AUAudioFrameCount shift) {
    if (left_ == nullptr) return;
    left_ += shift;
    right_ += shift;
  }

private:
  SF2::AUValue* left_{nullptr};
  SF2::AUValue* right_{nullptr};
};

} // end namespace
