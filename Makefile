PLATFORM_IOS = iOS Simulator,name=iPad mini (6th generation)
DERIVED_DATA_IOS = $(PWD)/.DerivedData-ios

PLATFORM_MACOS = macOS
DERIVED_DATA_MACOS = $(PWD)/.DerivedData-macos

TARGET = SF2Lib
QUIET = -quiet
SCHEME = -scheme 'SF2Lib-Package (Release)'

default: test

clean:
	@echo "-- removing coverage.txt percentage.txt "$(DERIVED_DATA_MACOS)" "$(DERIVED_DATA_IOS)""
	@-rm -rf coverage.txt percentage.txt "$(DERIVED_DATA_MACOS)" "$(DERIVED_DATA_IOS)"

resolve-deps: clean
	swift package resolve

test-ios: resolve-deps
	xcodebuild test \
		$(QUIET) \
		$(SCHEME) \
		-derivedDataPath "$(DERIVED_DATA_IOS)" \
		-destination platform="$(PLATFORM_IOS)"

test-macos: resolve-deps
	xcodebuild test \
		$(QUIET) \
		$(SCHEME) \
		-derivedDataPath "$(DERIVED_DATA_MACOS)" \
		-destination platform="$(PLATFORM_MACOS)" \
		-enableCodeCoverage YES

coverage: test-macos
	@xcrun xccov view --report --only-targets $(DERIVED_DATA_MACOS)/Logs/Test/*.xcresult > coverage.txt
	@cat coverage.txt

percentage: coverage
	@awk '/ $(TARGET) / { if ($$3 > 0) print $$4; }' coverage.txt > percentage.txt
	@cat percentage.txt

post: percentage
	@if [[ -n "$$GITHUB_ENV" ]]; then \
		echo "PERCENTAGE=$$(< percentage.txt)" >> $$GITHUB_ENV; \
	fi

test: test-ios post

.PHONY: test post percentage coverage test-macos test-ios resolve-deps clean
