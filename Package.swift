// swift-tools-version:5.5

import PackageDescription

let package = Package(
  name: "SF2Lib",
  platforms: [.iOS(.v13), .macOS(.v10_15)],
  products: [
    .library(
      name: "SF2Lib",
      targets: ["SF2Lib"]),
    .executable(name: "DSPTableGenerator", targets: ["DSPTableGenerator"])
  ],
  dependencies: [
    .package(name: "AUv3SupportPackage", url: "https://github.com/bradhowes/AUv3Support", branch: "main"),
  ],
  targets: [
    .target(
      name: "SF2Lib",
      dependencies: [
        .productItem(name: "AUv3-DSP-Headers", package: "AUv3SupportPackage", condition: .none),
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
        .unsafeFlags(["-fmodules", "-fcxx-modules"], .none)
      ]
    ),
    .executableTarget(
      name: "DSPTableGenerator",
      dependencies: [
        .target(name: "SF2Lib", condition: .none),
      ],
      cxxSettings: [
        .define("USE_ACCELERATE", to: "1", .none),
        .unsafeFlags(["-fmodules", "-fcxx-modules"], .none)
      ]
    ),
    .testTarget(
      name: "SF2LibTests",
      dependencies: ["SF2Lib"],
      resources: [
        .process("Resources")
      ],
      cxxSettings: [
        // Set to 1 to play audio in tests. Set to 0 to keep silent.
        .define("PLAY_AUDIO", to: "0", .none),
        .unsafeFlags(["-fmodules", "-fcxx-modules"], .none)
      ]
    )
  ],
  cxxLanguageStandard: .cxx17
)
