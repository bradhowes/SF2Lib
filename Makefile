PLATFORM_IOS = iOS Simulator,name=iPad mini (6th generation)
PLATFORM_MACOS = macOS
TARGET = SF2Lib
DOCC_DIR = ./docs
QUIET = -quiet
WORKSPACE = $(PWD)/.workspace
DEST = -scheme SF2Lib-Package -destination platform="$(PLATFORM_MACOS)"

default: percentage

clean:
	rm -rf "$(PWD)/.DerivedData-macos" "$(PWD)/.DerivedData-ios" "$(WORKSPACE)"

docc:
	DOCC_JSON_PRETTYPRINT="YES" \
	swift package \
		--allow-writing-to-directory $(DOCC_DIR) \
		generate-documentation \
		--target $(TARGET) \
		--disable-indexing \
		--transform-for-static-hosting \
		--hosting-base-path swift-math-parser \
		--output-path $(DOCC_DIR)

resolve-deps: clean
	xcodebuild \
		$(QUIET) \
		-resolvePackageDependencies \
		-clonedSourcePackagesDirPath "$(WORKSPACE)" \
		-scheme $(TARGET)

test-ios: resolve-deps
	xcodebuild test \
		$(QUIET) \
		-clonedSourcePackagesDirPath "$(WORKSPACE)" \
		-scheme $(TARGET) \
		-derivedDataPath "$(PWD)/.DerivedData-ios" \
		-destination platform="$(PLATFORM_IOS)"

test-macos: resolve-deps
	xcodebuild build-for-testing \
		$(QUIET) \
		-clonedSourcePackagesDirPath "$(WORKSPACE)" \
		-scheme $(TARGET) \
		-derivedDataPath "$(PWD)/.DerivedData-macos" \
		-destination platform="$(PLATFORM_MACOS)"
	xcodebuild test-without-building \
		$(QUIET) \
		-clonedSourcePackagesDirPath "$(WORKSPACE)" \
		-scheme $(TARGET) \
		-derivedDataPath "$(PWD)/.DerivedData-macos" \
		-destination platform="$(PLATFORM_MACOS)" \
		-enableCodeCoverage YES

coverage: test-macos
	xcrun xccov view --report --only-targets $(PWD)/.DerivedData-macos/Logs/Test/*.xcresult > coverage.txt
	cat coverage.txt

percentage: coverage
	awk '/ $(TARGET) / { if ($$3 > 0) print $$4; }' coverage.txt > percentage.txt
	cat percentage.txt

post: percentage
	@if [[ -n "$$GITHUB_ENV" ]]; then \
		echo "PERCENTAGE=$$(< percentage.txt)" >> $$GITHUB_ENV; \
	fi

test: test-io percentage

.PHONY: coverage clean build test post percentage coverage
