# Fuzzing

`SF2FileFuzzer.mm` is a [libFuzzer](https://llvm.org/docs/LibFuzzer.html) target. Each input is loaded with
`IO::File::load(fd)`. If it loads, it is put through the same steps a host would take: build the `PresetCollection`,
load each preset's samples, then configure, start and render a voice for the zones that match a few key/velocity pairs.
The target is built with AddressSanitizer and UndefinedBehaviorSanitizer, and with `CHECKED_VECTOR_INDEXING=1`.

Apple clang ships without the libFuzzer runtime, so the build uses Homebrew LLVM (`brew install llvm`):

```sh
make fuzz                 # build, write the seed corpus, fuzz for 60 seconds
make fuzz FUZZ_TIME=600   # fuzz for 10 minutes
```

The build output, the corpus and any crashing inputs (`crash-*`) all go into `.fuzz/`, which is not committed. To
replay a crash, run `.fuzz/sf2-file-fuzzer .fuzz/crash-<hash>`.

`MakeSeeds.cpp` writes a few small, valid SF2 files built with `Sources/TestUtils/SF2Builder.hpp` into the corpus. The
SF2 files in `Sources/TestUtils/Resources` are several megabytes each, far too big to make useful seeds.

`MalformedFileTests.testRandomByteCorruptionNeverCrashes` runs a small, deterministic version of the same idea as part
of the normal test suite.
