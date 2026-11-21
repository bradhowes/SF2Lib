PLATFORM_IOS = iOS Simulator,name=iPad mini (A17 Pro)
PLATFORM_MACOS = macOS
XCCOV = xcrun xccov view --report --only-targets
SCHEME = 'SF2Lib-Package (Release)'
BUILD_FLAGS = -skipMacroValidation -skipPackagePluginValidation -enableCodeCoverage YES -scheme $(SCHEME)

ifeq ($(GITHUB_ENV),)
XCB = | xcbeautify --renderer github-actions
endif

default: report

test-iOS:
	rm -rf "$(PWD)/.DerivedData-iOS"
	xcodebuild -list
	set -o pipefail && xcodebuild test $(BUILD_FLAGS) \
		-derivedDataPath "$(PWD)/.DerivedData-iOS" \
		-destination platform="$(PLATFORM_IOS)" $(XCB)

coverage-iOS: test-iOS
	$(XCCOV) $(PWD)/.DerivedData-iOS/Logs/Test/*.xcresult > coverage_iOS.txt
	echo "iOS Coverage:"
	cat coverage_iOS.txt

percentage-iOS: coverage-iOS
	awk '/ SF2Lib / { print $$4 }' coverage_iOS.txt > percentage_iOS.txt
	echo "iOS Coverage Pct:"
	cat percentage_iOS.txt

test-macOS:
	rm -rf "$(PWD)/.DerivedData-macOS"
	set -o pipefail && xcodebuild test $(BUILD_FLAGS) \
		-derivedDataPath "$(PWD)/.DerivedData-macOS" \
		-destination platform="$(PLATFORM_MACOS)" $(XCB)

coverage-macOS: test-macOS
	$(XCCOV) $(PWD)/.DerivedData-macOS/Logs/Test/*.xcresult > coverage_macOS.txt
	echo "macOS Coverage:"
	cat coverage_macOS.txt

percentage-macOS: coverage-macOS
	awk '/ SF2Lib / { print $$4 }' coverage_macOS.txt > percentage_macOS.txt
	echo "macOS Coverage Pct:"
	cat percentage_macOS.txt

report: percentage-iOS percentage-macOS
	@if [[ -n "$$GITHUB_ENV" ]]; then \
        echo "PERCENTAGE=$$(< percentage_macOS.txt)" >> $$GITHUB_ENV; \
    fi

# libFuzzer target for SF2 parsing (Fuzz/SF2FileFuzzer.mm). Apple clang ships without the libFuzzer runtime, so this
# uses Homebrew LLVM (`brew install llvm`). Run `make fuzz FUZZ_TIME=600` for a longer session. Crashing inputs are
# written to .fuzz/.
FUZZ_LLVM ?= /opt/homebrew/opt/llvm
FUZZ_CXX = $(FUZZ_LLVM)/bin/clang++
FUZZ_TIME ?= 60
FUZZ_OUT = $(PWD)/.fuzz
FUZZ_SDK = $(shell xcrun --show-sdk-path)
FUZZ_DSPHEADERS = $(PWD)/.build/checkouts/DSPHeaders/Sources/DSPHeaders
FUZZ_SOURCES = $(shell find Sources/SF2File Sources/SF2Util Sources/SF2Lib -name '*.mm' -not -path '*/.~/*') \
	$(wildcard $(FUZZ_DSPHEADERS)/*.mm)
FUZZ_FLAGS = -std=c++2b -g -O1 -isysroot $(FUZZ_SDK) -fobjc-arc \
	-ISources/SF2File/include -ISources/SF2Util/include -ISources/SF2Lib/include -I$(FUZZ_DSPHEADERS)/include \
	-DCHECKED_VECTOR_INDEXING=1 -DENABLE_LOWPASS_FILTER=1 -DPLAY_AUDIO=0 -DUSE_ACCELERATE=1
FUZZ_LDFLAGS = -L$(FUZZ_LLVM)/lib/c++ -Wl,-rpath,$(FUZZ_LLVM)/lib/c++ \
	-framework Foundation -framework Accelerate -framework AudioToolbox -framework AVFoundation

fuzz-build:
	swift package resolve
	mkdir -p $(FUZZ_OUT)/corpus
	$(FUZZ_CXX) -std=c++2b -isysroot $(FUZZ_SDK) -ISources/TestUtils Fuzz/MakeSeeds.cpp $(FUZZ_LDFLAGS) \
		-o $(FUZZ_OUT)/make-seeds
	$(FUZZ_OUT)/make-seeds $(FUZZ_OUT)/corpus
	$(FUZZ_CXX) $(FUZZ_FLAGS) -fsanitize=fuzzer,address,undefined Fuzz/SF2FileFuzzer.mm $(FUZZ_SOURCES) \
		$(FUZZ_LDFLAGS) -o $(FUZZ_OUT)/sf2-file-fuzzer

fuzz: fuzz-build
	$(FUZZ_OUT)/sf2-file-fuzzer -max_total_time=$(FUZZ_TIME) -max_len=65536 -artifact_prefix=$(FUZZ_OUT)/ \
		$(FUZZ_OUT)/corpus

.PHONY: report test-iOS test-macOS coverage-iOS coverage-macOS coverage-iOS percentage-macOS percentage-iOS fuzz fuzz-build

clean:
	-rm -rf $(PWD)/.DerivedData-macOS $(PWD)/.DerivedData-iOS coverage*.txt percentage*.txt
