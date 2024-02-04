// swift-tools-version:5.9

import PackageDescription

let package = Package(
  name: "SF2Lib",
  platforms: [.iOS(.v13), .macOS(.v10_15), .tvOS(.v12)],
  products: [
    .library(name: "SF2Lib", targets: ["SF2Lib"]),
    .library(name: "Engine", targets: ["Engine"])
  ],
  dependencies: [.package(url: "https://github.com/bradhowes/AUv3Support", from: "10.1.0")],
  targets: [
    .target(
      name: "Engine",
      dependencies: ["SF2Lib"],
      path: "Sources/Engine",
      publicHeadersPath: "include"
    ),
    .target(
      name: "TestUtils",
      dependencies: ["SF2Lib"],
      path: "SOurces/TestUtils",
      resources: [.process("Resources")],
      publicHeadersPath: ""
    ),
    .testTarget(
      name: "EngineTests",
      dependencies: ["Engine", "TestUtils"]
    ),
    .target(
      name: "SF2Lib",
      dependencies: [.product(name: "AUv3-DSP-Headers", package: "AUv3Support", condition: .none)],
      path: "Sources/SF2Lib",
      exclude: [
        "Entity/README.md",
        "Entity/Generator/README.md",
        "Entity/Modulator/README.md",
        "IO/README.md",
        "MIDI/README.md",
        "Render/README.md"
      ],
      resources: [.process("Resources")],
      publicHeadersPath: "include",
      cxxSettings: [
        .define("USE_ACCELERATE", to: "1", .none),
        // Set to 1 to assert if std::vector[] index is invalid
        .define("CHECKED_VECTOR_INDEXING", to: "0", .none),
        // NOTE: having unsafeFlags set will cause SPM to deny use of this package by version.
        // Use the Engine target instead of this.
        .unsafeFlags([
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
        ], .none)
      ],
      swiftSettings: [
        .define("APPLICATION_EXTENSION_API_ONLY")
      ],
      linkerSettings: [
        .linkedFramework("Accelerate", .none),
        .linkedFramework("AudioToolbox", .none),
        .linkedFramework("AVFoundation", .none),
        .unsafeFlags(["-Xlinker", "-no_application_extension"])
      ]
    ),
    .testTarget(
      name: "SF2LibTests",
      dependencies: ["SF2Lib", "TestUtils"],
      cxxSettings: [
        // Set to 1 to play audio in tests. Set to 0 to keep silent.
        .define("PLAY_AUDIO", to: "0"),
        .unsafeFlags([
          "-Wno-newline-eof", // resource_bundle_accessor.h is missing newline at end of file
        ], .none)
      ],
      linkerSettings: []
    )
  ],
  cxxLanguageStandard: .cxx20
)
