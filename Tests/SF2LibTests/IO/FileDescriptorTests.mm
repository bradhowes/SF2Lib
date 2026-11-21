// Copyright © 2026 Brad Howes. All rights reserved.

#include <fcntl.h>
#include <unistd.h>

#include <XCTest/XCTest.h>

#include "SampleBasedContexts.hpp"
#include "SF2Builder.hpp"

#include "SF2File/IO/File.hpp"
#include "SF2File/IO/Parser.hpp"
#include "SF2File/IO/UniqueFd.hpp"
#include "SF2Lib/Render/PresetCollection.hpp"

using namespace SF2;
using LoadResponse = SF2::IO::File::LoadResponse;

/// @returns the number of file descriptors open in this process
static int openDescriptorCount()
{
  int count = 0;
  for (int fd = 0; fd < ::getdtablesize(); ++fd) {
    if (::fcntl(fd, F_GETFD) != -1) ++count;
  }
  return count;
}

static bool isOpen(int fd) { return ::fcntl(fd, F_GETFD) != -1; }

@interface FileDescriptorTests : SamplePlayingTestCase
@end

@implementation FileDescriptorTests

- (void)testUniqueFdClosesOnDestruction {
  auto path = self.contexts->context0.path();
  int raw = -1;
  {
    auto fd = IO::UniqueFd::openForReading(path.c_str());
    XCTAssertTrue(fd.isValid());
    raw = fd.get();
    XCTAssertTrue(isOpen(raw));
  }
  XCTAssertFalse(isOpen(raw));
}

- (void)testUniqueFdMoveTransfersOwnership {
  auto path = self.contexts->context0.path();
  auto first = IO::UniqueFd::openForReading(path.c_str());
  int raw = first.get();
  auto second{std::move(first)};
  XCTAssertFalse(first.isValid());
  XCTAssertEqual(second.get(), raw);

  IO::UniqueFd third;
  third = std::move(second);
  XCTAssertFalse(second.isValid());
  XCTAssertEqual(third.get(), raw);
  XCTAssertTrue(isOpen(raw));

  third.reset();
  XCTAssertFalse(third.isValid());
  XCTAssertFalse(isOpen(raw));
}

- (void)testUniqueFdDuplicateIsIndependent {
  auto path = self.contexts->context0.path();
  int original = ::open(path.c_str(), O_RDONLY);
  auto copy = IO::UniqueFd::duplicate(original);
  XCTAssertTrue(copy.isValid());
  XCTAssertNotEqual(copy.get(), original);
  ::close(original);
  XCTAssertTrue(isOpen(copy.get()));

  char buffer[4];
  XCTAssertEqual(::pread(copy.get(), buffer, 4, 0), 4);
  XCTAssertEqual(std::string(buffer, 4), "RIFF");
}

- (void)testUniqueFdInvalidInputs {
  XCTAssertFalse(IO::UniqueFd().isValid());
  XCTAssertFalse(IO::UniqueFd(-5).isValid());
  XCTAssertFalse(IO::UniqueFd::duplicate(-1).isValid());
  XCTAssertFalse(IO::UniqueFd::openForReading("/this/does/not/exist").isValid());
}

- (void)testLoadFromPathDoesNotLeakDescriptors {
  // `File::load()` used to open the file and never close it: one descriptor leaked per load.
  auto path = self.contexts->context0.path();
  auto before = openDescriptorCount();
  {
    std::vector<IO::File> files;
    for (int count = 0; count < 25; ++count) {
      files.emplace_back(path);
      XCTAssertEqual(files.back().load(), LoadResponse::ok);
    }
    // Each loaded file keeps exactly one descriptor for lazy sample loading.
    XCTAssertEqual(openDescriptorCount(), before + 25);
  }
  XCTAssertEqual(openDescriptorCount(), before);
}

- (void)testFailedLoadsDoNotLeakDescriptors {
  auto path = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibTruncated.sf2";
  auto bytes = SF2Builder::minimal().build();
  bytes.resize(bytes.size() / 2);
  {
    std::ofstream os(path, std::ios::binary | std::ios::trunc);
    os.write(reinterpret_cast<const char*>(bytes.data()), std::streamsize(bytes.size()));
  }
  auto before = openDescriptorCount();
  for (int count = 0; count < 25; ++count) {
    IO::File file{path};
    XCTAssertEqual(file.load(), LoadResponse::invalidFormat);
    XCTAssertEqual(openDescriptorCount(), before);
  }
}

- (void)testLoadFromDescriptorSurvivesCallerClosingIt {
  // This is what happens on the bookmark path: the NSFileHandle that supplied the descriptor is released (closing it)
  // right after `File::load(fd)`. Samples are loaded later, on a program change, so `File` needs its own descriptor.
  auto path = self.contexts->context0.path();

  // Reference samples, loaded from a file opened by path.
  IO::File referenceFile{path};
  XCTAssertEqual(referenceFile.load(), LoadResponse::ok);
  Render::PresetCollection referencePresets;
  referencePresets.build(referenceFile);
  XCTAssertTrue(referencePresets[0].loadSamples(referenceFile));
  auto reference = referencePresets[0].find(60, 127).at(0).samples();

  for (bool reuseDescriptor : {false, true}) {
    int fd = ::open(path.c_str(), O_RDONLY);
    IO::File file;
    XCTAssertEqual(file.load(fd), LoadResponse::ok);
    ::close(fd);

    // Without the fix, reads on the closed descriptor fail. Worse, if its number is reused by an unrelated file (here
    // /dev/zero), they quietly return that file's bytes instead.
    int other = reuseDescriptor ? ::open("/dev/zero", O_RDONLY) : -1;

    Render::PresetCollection presets;
    presets.build(file);
    XCTAssertTrue(presets[0].loadSamples(file), @"reuse %d", reuseDescriptor);
    auto configs = presets[0].find(60, 127);
    XCTAssertFalse(configs.empty());
    if (!configs.empty()) {
      auto samples = configs[0].samples();
      XCTAssertEqual(samples->size(), reference->size());
      bool same = samples->size() == reference->size();
      for (size_t index = 0; same && index < samples->size(); ++index) same = (*samples)[index] == (*reference)[index];
      XCTAssertTrue(same, @"reuse %d", reuseDescriptor);
    }
    if (other != -1) ::close(other);
  }
}

- (void)testMovedFileKeepsDescriptor {
  // `File(File&&) = default` used to copy a plain int, so both instances would have closed it.
  auto path = self.contexts->context0.path();
  auto before = openDescriptorCount();
  {
    IO::File original{path};
    XCTAssertEqual(original.load(), LoadResponse::ok);
    IO::File moved{std::move(original)};
    XCTAssertEqual(openDescriptorCount(), before + 1);
    Render::PresetCollection presets;
    presets.build(moved);
    XCTAssertTrue(presets[0].loadSamples(moved));
  }
  XCTAssertEqual(openDescriptorCount(), before);
}

- (void)testParserDoesNotLeakDescriptors {
  // `Parser::parse` never closed its descriptor, even on success.
  auto path = self.contexts->context0.path();
  auto before = openDescriptorCount();
  for (int count = 0; count < 10; ++count) {
    auto info = IO::Parser::parse(path.c_str());
    XCTAssertFalse(info.presets.empty());
  }
  XCTAssertEqual(openDescriptorCount(), before);

  auto bad = std::string(NSTemporaryDirectory().UTF8String) + "SF2LibParserBad.sf2";
  auto bytes = SF2Builder::minimal().build();
  bytes.resize(100);
  {
    std::ofstream os(bad, std::ios::binary | std::ios::trunc);
    os.write(reinterpret_cast<const char*>(bytes.data()), std::streamsize(bytes.size()));
  }
  for (int count = 0; count < 10; ++count) {
    bool threw = false;
    try {
      IO::Parser::parse(bad.c_str());
    } catch (LoadResponse) {
      threw = true;
    }
    XCTAssertTrue(threw);
  }
  XCTAssertEqual(openDescriptorCount(), before);
}

@end
