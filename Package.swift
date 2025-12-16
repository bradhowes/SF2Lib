// swift-tools-version:6.2

import PackageDescription

let unsafeFlags = [
  "-O3",
  "-pedantic",
  "-Wall",
  "-Wassign-enum",
  "-Wbad-function-cast",
  "-Wbind-to-temporary-copy",
  "-Wbool-conversion",
  "-Wbool-operation",
  "-Wc++11-extra-semi",
  "-Wcast-align",
  "-Wcast-function-type",
  "-Wcast-qual",
  "-Wchar-subscripts",
  "-Wcomma",
  "-Wcompletion-handler",
  "-Wconditional-uninitialized",
  "-Wconsumed",
  "-Wconversion",
  "-Wcovered-switch-default",
  "-Wdeclaration-after-statement",
  "-Wdeprecated",
  "-Wdeprecated-copy",
  "-Wdeprecated-copy-with-user-provided-dtor",
  "-Wdeprecated-dynamic-exception-spec",
  "-Wdeprecated-implementations",
  "-Wdirect-ivar-access",
  "-Wdocumentation",
  "-Wdocumentation-pedantic",
  // "-Wdouble-promotion",
  "-Wduplicate-decl-specifier",
  "-Wduplicate-enum",
  "-Wduplicate-method-arg",
  "-Wduplicate-method-match",
  "-Weffc++",
  "-Wempty-init-stmt",
  "-Wempty-translation-unit",
  "-Wenum-conversion",
  "-Wexplicit-ownership-type",
  "-Wfloat-conversion",
  "-Wfor-loop-analysis",
  "-Wformat-nonliteral",
  "-Wformat-type-confusion",
  "-Wframe-address",
  // "-Wglobal-constructors",
  "-Wheader-hygiene",
  "-Widiomatic-parentheses",
  "-Wimplicit-fallthrough",
  "-Wimplicit-retain-self",
  "-Wincompatible-function-pointer-types",
  "-Wlogical-op-parentheses",
  "-Wmethod-signatures",
  "-Wmismatched-tags",
  "-Wmissing-braces",
  "-Wmissing-field-initializers",
  "-Wmissing-method-return-type",
  "-Wmissing-noreturn",
  // "-Wmissing-prototypes",
  "-Wmissing-variable-declarations",
  "-Wmove",
  "-Wno-newline-eof", // resource_bundle_accessor.h is missing newline at end of file
  "-Wno-unknown-pragmas",
  "-Wnon-virtual-dtor",
  "-Wnullable-to-nonnull-conversion",
  "-Wobjc-interface-ivars",
  "-Wobjc-missing-property-synthesis",
  "-Wobjc-property-assign-on-object-type",
  "-Wobjc-signed-char-bool-implicit-int-conversion",
  "-Wold-style-cast",
  "-Wover-aligned",
  "-Woverlength-strings",
  "-Woverriding-method-mismatch",
  // "-Wpadded",
  "-Wparentheses",
  "-Wpessimizing-move",
  "-Wpointer-arith",
  "-Wrange-loop-analysis",
  "-Wredundant-move",
  "-Wreorder",
  "-Wself-assign-overloaded",
  "-Wself-move",
  "-Wsemicolon-before-method-body",
  "-Wshadow-all",
  "-Wshorten-64-to-32",
  "-Wsign-compare",
  "-Wsign-conversion",
  "-Wsometimes-uninitialized",
  "-Wstrict-selector-match",
  "-Wstring-concatenation",
  "-Wstring-conversion",
  "-Wsuggest-destructor-override",
  "-Wsuggest-override",
  "-Wsuper-class-method-mismatch",
  // "-Wswitch-enum",
  "-Wundefined-internal-type",
  "-Wundefined-reinterpret-cast",
  "-Wuninitialized",
  "-Wuninitialized-const-reference",
  "-Wunneeded-internal-declaration",
  "-Wunneeded-member-function",
  "-Wunreachable-code-aggressive",
  // "-Wunsafe-buffer-usage",
  "-Wunused",
  "-Wunused-function",
  "-Wunused-label",
  "-Wunused-parameter",
  "-Wunused-private-field",
  "-Wunused-value",
  "-Wunused-variable",
  // "-Wzero-as-null-pointer-constant",
  "-Wzero-length-array",
  "-x", "objective-c++", // treat source files as Obj-C++ files
]

// Set to true to enable C++ bounds checking
let checkedVectorIndexing = false
// Set to true to enable low-pass filter in sample generation (once sound quality bugs are fixed)
let enableLowPassFilter = false
// Set to true to play audio in tests. Set to false to keep silent.
let playAudio = true
// Set to true to enable Accelerate framework
let useAccelerate = true
// Set to true to use local DSPHeaders sources
let useLocalDSPHeaders = false
// Set to true to use "unsafe" C++ flags (here, unsafe means that there is no checking by SPM that they are valid for the compile
// chain being used).
let useUnsafeFlags = false // ProcessInfo.processInfo.environment["USE_UNSAFE_FLAGS"] != nil

var cxxSettings: [CXXSetting] = [
  .define("CHECKED_VECTOR_INDEXING", to: checkedVectorIndexing ? "1" : "0", .none),
  .define("ENABLE_LOWPASS_FILTER", to: enableLowPassFilter ? "1" : "0", .none),
  .define("PLAY_AUDIO", to: playAudio ? "1" : "0", .none),
  .define("USE_ACCELERATE", to: useAccelerate ? "1" : "0", .none)
]

if useUnsafeFlags {
  cxxSettings.append(.unsafeFlags(unsafeFlags, .when(configuration: .debug)))
}

let swiftSettings: [SwiftSetting] = [
  .define("APPLICATION_EXTENSION_API_ONLY")
]

let dspHeaders: Package.Dependency = useLocalDSPHeaders ? .package(
  name: "DSPHeaders",
  path: "/Users/howes/src/Mine/DSPHeaders"
) : .package(
  url: "https://github.com/bradhowes/DSPHeaders",
  from: "1.2.1"
)

let package = Package(
  name: "SF2Lib",
  platforms: [.iOS(.v14), .macOS(.v14), .tvOS(.v16)],
  products: [
    .library(name: "Engine", targets: ["Engine"]),
    .library(name: "SF2File", targets: ["SF2File"]),
    .library(name: "SF2Lib", targets: ["SF2Lib"])
  ],
  dependencies: [
    dspHeaders
  ],
  targets: [
    .target(
      name: "Engine",
      dependencies: ["SF2Lib"],
      path: "Sources/Engine",
      publicHeadersPath: "include",
      swiftSettings: [.interoperabilityMode(.Cxx)]
    ),
    .target(
      name: "SF2Lib",
      dependencies: [
        "SF2File",
        "SF2Util",
        .product(name: "DSPHeaders", package: "DSPHeaders")
      ],
      path: "Sources/SF2Lib",
      resources: [.process("Resources")],
      publicHeadersPath: "include",
      cxxSettings: cxxSettings,
      swiftSettings: swiftSettings,
      linkerSettings: [
        .linkedFramework("Accelerate", .none),
        .linkedFramework("AudioToolbox", .none),
        .linkedFramework("AVFoundation", .none),
      ]
    ),
    .target(
      name: "SF2File",
      dependencies: [
        "SF2Util",
        .product(name: "DSPHeaders", package: "DSPHeaders")
      ],
      path: "Sources/SF2File",
      publicHeadersPath: "include",
      cxxSettings: cxxSettings,
      swiftSettings: swiftSettings,
      linkerSettings: [
        .linkedFramework("AudioToolbox", .none),
        .linkedFramework("AVFoundation", .none),
      ]
    ),
    .target(
      name: "SF2Util",
      dependencies: [
        .product(name: "DSPHeaders", package: "DSPHeaders")
      ],
      path: "Sources/SF2Util",
      publicHeadersPath: "include",
      cxxSettings: cxxSettings,
      swiftSettings: swiftSettings,
      linkerSettings: [
        .linkedFramework("AudioToolbox", .none),
        .linkedFramework("AVFoundation", .none),
      ]
    ),
    .target(
      name: "TestUtils",
      dependencies: [
        "SF2Lib",
        .product(name: "DSPHeaders", package: "DSPHeaders")
      ],
      path: "Sources/TestUtils",
      resources: [.process("Resources")],
      publicHeadersPath: "",
      cxxSettings: cxxSettings
    ),
    .testTarget(
      name: "EngineTests",
      dependencies: ["Engine", "TestUtils"],
      cxxSettings: cxxSettings
    ),
    .testTarget(
      name: "SF2LibTests",
      dependencies: ["SF2Lib", "TestUtils"],
      cxxSettings: cxxSettings + [
        .unsafeFlags([
          "-Wno-newline-eof", // resource_bundle_accessor.h is missing newline at end of file
        ], .none)
      ],
      linkerSettings: []
    )
  ],
  cxxLanguageStandard: .cxx2b
)
