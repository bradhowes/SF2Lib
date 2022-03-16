// Copyright © 2022 Brad Howes. All rights reserved.

#pragma once

#include <iostream>

#include "SF2Lib/DSP/DSP.hpp"
#include "SF2Lib/MIDI/ValueTransformer.hpp"

namespace SF2::DSP::Tables {

/**
 Table value generators and initializers. This is only used by the DSPGenerators program which creates the DSP tables
 at compile time for quick loading at runtime.
 */
struct Generator {
  std::ostream& os_;
  
  /**
   Generic table generator. The template type `T` must define a `TableSize` class parameter that gives the size of the
   table to initialize, and it must define a `Value` class method that takes an index value and returns a value to
   put into the table.
   
   @param name the name of the table to initialize
   */
  template <typename T>
  void generate(const std::string& name) noexcept {
    os_ << "const std::array<double, " << name << "::TableSize> " << name << "::lookup_ = {\n";
    for (auto index = 0; index < T::TableSize; ++index) os_ << T::value(index) << ",\n";
    os_ << "};\n\n";
  }

  /**
   Generic ValueTransformer table initializer.
   
   @param proc the function that generates a value for a given table index
   @param name the table name to initialize
   @param bipolar if true, initialize a bipolar table; otherwise, a unipolar one (default).
   */
  void generateTransform(std::function<double(int)> proc, const std::string& name, bool bipolar = false) noexcept {
    os_ << "const ValueTransformer::TransformArrayType ValueTransformer::" << name;
    if (bipolar) os_ << "Bipolar";
    os_ << "_ = {\n";

    auto func = bipolar ? [=](auto index) { return unipolarToBipolar(proc(index)); } : proc;
    for (auto index = 0; index < MIDI::ValueTransformer::TableSize; ++index) os_ << func(index) << ",\n";
    os_ << "};\n\n";
  }

  Generator(std::ostream& os) noexcept;
};

} // SF2::DSP::Tables
