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
    // .package(name: "AUv3SupportPackage", url: "https://github.com/bradhowes/AUv3Support", branch: "main"),
    .package(name: "AUv3SupportPackage", path: "../AUv3Support")
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
        .define("USE_ACCELERATE", to: "1", .none),
        .unsafeFlags([
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
        ], .none)
      ],
      linkerSettings: [
        .linkedFramework("Accelerate", .none),
        .linkedFramework("AudioToolbox", .none),
        .linkedFramework("AVFoundation", .none)
      ]
    ),
    .executableTarget(
      name: "DSPTableGenerator",
      dependencies: [
        .target(name: "SF2Lib", condition: .none),
      ],
      cxxSettings: [
        .define("USE_ACCELERATE", to: "1", .none)
      ],
      linkerSettings: [.linkedFramework("Accelerate", .none)]
    ),
    .testTarget(
      name: "SF2LibTests",
      dependencies: ["SF2Lib"],
      resources: [
        .process("Resources")
      ],
      cxxSettings: [
        // Set to 1 to play audio in tests. Set to 0 to keep silent.
        .define("PLAY_AUDIO", to: "0", .none)
      ],
      linkerSettings: [
        .linkedFramework("Accelerate", .none),
        .linkedFramework("AudioToolbox", .none),
        .linkedFramework("AVFoundation", .none)
      ]
    )
  ],
  cxxLanguageStandard: .cxx17
)

//-Wmissing-field-initializers
//-Wmissing-prototypes
//-Werror\=return-type
//-Wdocumentation
//-Wunreachable-code
//-Wquoted-include-in-framework-header
//-Wframework-include-private-from-public
//-Wno-implicit-atomic-properties
//-Werror\=deprecated-objc-isa-usage
//-Wno-objc-interface-ivars
//-Werror\=objc-root-class
//-Wno-arc-repeated-use-of-weak
//-Wimplicit-retain-self
//-Wnon-virtual-dtor
//-Woverloaded-virtual
//-Wno-exit-time-destructors
//-Wduplicate-method-match
//-Wmissing-braces
//-Wparentheses
//-Wswitch
//-Wcompletion-handler
//-Wunused-function
//-Wunused-label
//-Wunused-parameter
//-Wunused-variable
//-Wunused-value
//-Wempty-body
//-Wno-unknown-pragmas
//-pedantic
//-Wshadow
//-Wfour-char-constants
//-Wnon-literal-null-conversion
//-Wobjc-literal-conversion

//-Wmissing-braces
//-Wparentheses
//-Wswitch
//-Wcompletion-handler
//-Wunused-function
//-Wunused-label
//-Wunused-parameter
//-Wunused-variable
//-Wunused-value
//-Wempty-body
//-Wno-unknown-pragmas
//-Wuninitialized
//-Wconditional-uninitialized
//-Wconversion
//-Wconstant-conversion
//-Wassign-enum
//-Wsign-compare
//-Wint-conversion
//-Wbool-conversion
//-Wenum-conversion
//-Wfloat-conversion
//-Wshorten-64-to-32
//-Wsign-conversion
//-Wmove
//-Wcomma

//-Wno-newline-eof
//-Wno-selector
//-Wno-strict-selector-match

//-Wundeclared-selector
//-Wdeprecated-implementations
//-Wc++11-extensions
//
//-fstrict-aliasing
//-Wprotocol
//-Wdeprecated-declarations
//-Winvalid-offsetof
//-g -fvisibility-inlines-hidden
//-Wsign-conversion
//-Winfinite-recursion
//-Wmove
//-Wcomma
//-Wblock-capture-autoreleasing
//-Wstrict-prototypes
//-Wrange-loop-analysis
//-Wsemicolon-before-method-body
//-Wunguarded-availability
//-fobjc-abi-version\=2
//-fobjc-legacy-dispatch
//-fprofile-instr-generate
//-fcoverage-mapping
//-fsanitize\=undefined
//-fno-sanitize\=enum,return,float-divide-by-zero,function,vptr
