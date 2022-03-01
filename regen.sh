#!/bin/bash

swift build
$(swift build --show-bin-path)/DSPTableGenerator Sources/SF2Lib/DSP/DSPGenerated.cpp
