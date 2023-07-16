// swift-tools-version:5.7

import PackageDescription

let package = Package(
  name: "SF2Lib",
  platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v12)],
  products: [
    .library(
      name: "SF2Lib",
      targets: ["SF2Lib"])
  ],
  dependencies: [
    .package(url: "https://github.com/bradhowes/AUv3Support", branch: "main")
    // .package(name: "AUv3SupportPackage", path: "../AUv3Support")
  ],
  targets: [
    .target(
      name: "SF2Lib",
      dependencies: [
        .product(name: "AUv3-DSP-Headers", package: "AUv3Support", condition: .none),
      ],
      exclude: [
        "DSP/README.md",
        "Entity/README.md",
        "Entity/Generator/README.md",
        "Entity/Modulator/README.md",
        "IO/README.md",
        "MIDI/README.md",
        "Render/README.md"
      ],
      resources: [
        .process("Resources", localization: nil)
      ],
      cxxSettings: [
        .headerSearchPath("./include", .none),
        .define("USE_ACCELERATE", to: "1", .none),
        // Set to 1 to assert if std::vector[] index is invalid
        .define("CHECKED_VECTOR_INDEXING", to: "0", .none),
        .unsafeFlags([
          "-O3",
          "-pedantic",
          "-Wmissing-braces",
          "-Wparentheses",
          "-Wswitch",
          "-Wcompletion-handler",
          "-Wunused-function",
          "-Wunused-label",
          "-Wunused-parameter",
          "-Wunused-variable",
          "-Wunused-value",
          "-Wempty-body",
          "-Wno-unknown-pragmas",
          "-Wuninitialized",
          "-Wconditional-uninitialized",
          "-Wconversion",
          "-Wconstant-conversion",
          "-Wassign-enum",
          "-Wsign-compare",
          "-Wint-conversion",
          "-Wbool-conversion",
          "-Wenum-conversion",
          "-Wfloat-conversion",
          "-Wshorten-64-to-32",
          "-Wsign-conversion",
          "-Wmove",
          "-Wcomma",
          "-Wno-newline-eof", // resource_bundle_accessor.h is missing newline at end of file
          "-x", "objective-c++", // treat source files as Obj-C++ files
        ], .none)
      ],
      swiftSettings: [
        .define("APPLICATION_EXTENSION_API_ONLY")
      ],
      linkerSettings: [
        .linkedFramework("Accelerate", .none),
        .linkedFramework("AudioToolbox", .none),
        .linkedFramework("AVFoundation", .none)
      ]
    ),
    .testTarget(
      name: "SF2LibTests",
      dependencies: ["SF2Lib"],
      resources: [
        .process("Resources"),
      ],
      cxxSettings: [
        // Set to 1 to play audio in tests. Set to 0 to keep silent.
        .define("PLAY_AUDIO", to: "0"),
        .unsafeFlags([
          "-Wno-newline-eof", // resource_bundle_accessor.h is missing newline at end of file
          "-x", "objective-c++", // treat source files as Obj-C++ files
        ], .none)
      ],
      linkerSettings: [
        .linkedFramework("Accelerate", .none),
        .linkedFramework("AudioToolbox", .none),
        .linkedFramework("AVFoundation", .none),
        .linkedFramework("QuartzCore", .none),
        .linkedFramework("Foundation", .none),
        .linkedFramework("XCTest", .none),
      ]
    )
  ],
  cxxLanguageStandard: .cxx20
)

#if swift(>=5.6)
// Add the documentation compiler plugin if possible
package.dependencies.append(
  .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")
)
#endif
