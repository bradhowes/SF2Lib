# Semi-hacky way to get Emacs eglot with clangd to work OK on macOS. The use of Cmake here is solely for the purposes of
# generating a cmake/compile_commands.json file with the list of sources. There is an existing Makefile which is used
# for the Github CI pipeline, and it can also be used via the command-line.
#
# To rebuild the compile_commands.json file:
#
#   % cmake -S . -G "Unix Makefiles" -B cmake
#

cmake_minimum_required(VERSION 4.2)

project(SF2Lib)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(SDK "/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk")

file(GLOB_RECURSE Sources "${CMAKE_SOURCE_DIR}/Sources/*.mm")

# No idea what is really necessary here, but this seems to give clangd enough info to parse the Objective C++ files..
add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-g;-DDEBUG;-D__OBJC2__;-D__USE_PUBLIC_HEADERS__;-ObjC++;-std=c++2a;>")
add_compile_options("$<$<COMPILE_LANGUAGE:CXX>:-framework;Foundation;-isysroot;${SDK};>")

add_executable(SF2Lib ${Sources})

target_include_directories(
  SF2Lib PUBLIC
  "${CMAKE_SOURCE_DIR}/Sources/Engine/include"
  "${CMAKE_SOURCE_DIR}/Sources/SF2File/include"
  "${CMAKE_SOURCE_DIR}/Sources/SF2Lib/include"
  "${CMAKE_SOURCE_DIR}/Sources/SF2Util/include"

  # NOTE: expectation is that DSPHeaders is a sibling directory to SF2Lib
  "${CMAKE_SOURCE_DIR}/../DSPHeaders/Sources/DSPHeaders/include"
)
