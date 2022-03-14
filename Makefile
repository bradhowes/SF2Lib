PLATFORM_IOS = iOS Simulator,name=iPad mini (6th generation)
PLATFORM_MACOS = macOS

DEST = -scheme SF2Lib-Package -destination platform="$(PLATFORM_MACOS)"

default: post

build.run:
#   swift package generate-xcodeproj
	xcodebuild build $(DEST)
	touch build.run

build: build.run

test.run: build.run
	xcodebuild test $(DEST) -enableCodeCoverage YES ENABLE_TESTING_SEARCH_PATHS=YES -resultBundlePath $PWD
	touch test.run

test: test.run

# Extract coverage info for SF2Lib -- expects defintion of env variable GITHUB_ENV

cov.txt: test.run
	xcrun xccov view --report --only-targets WD.xcresult > cov.txt

coverage: cov.txt
	@cat cov.txt

PATTERN = SF2Lib.framework

percentage.txt: cov.txt
	awk '/$(PATTERN)/ {s+=$$4;++c} END {print s/c;}' < cov.txt > percentage.txt
	@cat percentage.txt

percentage: percentage.txt
	@cat percentage.txt

post: percentage
	@if [[ -n "$$GITHUB_ENV" ]]; then \
		echo "PERCENTAGE=$$(< percentage.txt)" >> $$GITHUB_ENV; \
	fi

clean:
	@echo "-- removing cov.txt percentage.txt"
	@-rm -rf cov.txt percentage.txt WD WD.xcresult build.run test.run
	@xcodebuild clean $(DEST)

.PHONY: coverage clean build test post percentage coverage
