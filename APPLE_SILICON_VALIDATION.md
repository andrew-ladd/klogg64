# Apple Silicon validation — 2026-09-22

## Outcome

The existing C++/Qt application builds and runs natively on Apple Silicon with
Vectorscan acceleration enabled. No core rewrite was required. The GUI loaded a
2 GiB synthetic log and returned the expected 2,048 regex matches.

This is a validated local prototype, not a signed/notarized public release.
The installed `/Applications/klogg.app` was not replaced.

## Environment and artifacts

- Apple M1 Pro, 10 CPU cores, 32 GiB RAM; macOS 27.0 (26A428).
- Apple Clang 21.0.0; macOS 27 SDK; CMake 4.4.3; Ninja 1.13.2.
- Qt 6.7.3, matching the repository's CI; Boost 1.92.0; Ragel 6.11.
- RelWithDebInfo, LTO enabled, ARM64, Vectorscan on, Hyperscan off,
  crash reporting off, allocator override off, warnings as errors enabled.
- Application version: 24.11.0.0. Binary deployment target: macOS 27.0.
- Build instructions: [BUILD.md](BUILD.md#apple-silicon-validation-build).
- Bundled local application: `build_root/validation/native/klogg.app` (about 60 MiB).
- Search executable: `build_root/output/klogg_grep`.
- Logs, benchmark script/data/results, and architecture inventory:
  `build_root/validation/` (ignored by Git).

The GUI executable and both test executables are ARM64 Mach-O binaries. All 20
Mach-O files in the deployed bundle contain ARM64 code; Qt's universal libraries
also contain Intel code. The bundle has a local ad-hoc signature, not a Developer
ID signature or notarization ticket.

## Verification

`ctest --test-dir build_root --output-on-failure` passed all three targets:

| Target | Result |
| --- | --- |
| `klogg_smoke` | Passed |
| `klogg_tests` | 4,058 assertions in 5 cases passed |
| `klogg_itests` | 938 assertions in 7 cases passed |

Total CTest time: 15.00 seconds. The added accelerated-backend test checks that a
simple regex creates `HsSingleMatcher`, rather than silently falling back to Qt,
and verifies matching and nonmatching input. Existing integration tests exercise
file updates, decoding, attachment/loading, search, and UI components. The main
window test remains excluded by the project's existing Apple-platform condition.

A separate GUI check verified the deployed bundle opening the 2 GiB file,
displaying 16,777,216 lines, accepting `ERROR [0-9]+`, rendering matching lines,
and reporting exactly 2,048 matches. This is a smoke check, not full UI regression
coverage, and does not establish complete log-rotation or sleep/wake correctness.

## Synthetic benchmark

Fixture: 2 GiB of 128-byte ASCII lines, 16,777,216 lines total. One ERROR record per
8,192-line block; the remainder are INFO records. The 1 MiB block is repeated
2,048 times. Three fresh processes per query, run sequentially using `klogg_grep`.
OS file caches were not flushed. Timings include the first run; these are
cache-warm, repetitive synthetic data results, not a storage-throughput claim.

| Query | Expected matches | Median index time | Median search time | Median process wall time | Peak RSS range |
| --- | ---: | ---: | ---: | ---: | ---: |
| `ERROR [0-9]+` | 2,048 | 553 ms | 450 ms | 1.101 s | 235–273 MiB |
| `IMPOSSIBLE_MATCH_[0-9]+` | 0 | 538 ms | 350 ms | 0.999 s | 219–239 MiB |

All six runs returned the correct counts. Index storage was reported as 22 MiB.
Index/search durations come from application instrumentation; wall time includes
startup and output. Resident-memory measurements come from macOS `/usr/bin/time
-l`, rather than the application's memory log.

The application currently logs virtual address-space usage as memory usage on
macOS (`src/crash_handler/src/memory_info.cpp`); on this ARM64 machine that reports
hundreds of GiB and is not a useful physical-memory measurement. It was not used
for the figures above.

An isolated copy of the installed Intel 22.06 app was tried as a Rosetta baseline,
but was killed before producing startup output, including after local signature
verification. Its failure cause is not established. No Intel timing or ARM speedup
claim is supported. Even a successful run would compare different application
versions; a controlled architecture comparison needs the same source revision.

## Compatibility changes made

- Removed Qt's obsolete AGL link dependency for 64-bit macOS builds. Older Qt can
  locate a host framework stub even though modern SDKs no longer ship the linker
  framework. Other Qt/OpenGL dependencies are preserved.
- Updated five user-defined literal declarations for current Clang syntax.
- Removed unnecessary virtual declarations in the final `VersionCheckerConfig`
  class; its persistence base dispatches through CRTP.
- Checked file-open results in the test writer helper.
- Added a test that proves the accelerated regex backend is selected.

The first attempt with Homebrew Qt 6.11.2 failed in the pinned KArchive dependency
on `QString::arg(QFlags)`. Qt 6.7.3 avoided that unrelated API migration. Downloaded
dependency sources were not patched. Qt 6.7 code generation also needed access
outside the sandbox for its CPU capability checks.

## Remaining release work

1. Choose an explicit minimum macOS version and CPU baseline, rebuild, and test
   on the oldest supported OS and other Apple Silicon models. This prototype
   inherits macOS 27.0 and `-march=native`, so it is not an older-macOS release.
2. Replace host-based architecture decisions in CMake with target-aware decisions;
   make `KLOGG_GENERIC_CPU` meaningful on ARM. Validate Intel separately if retaining it.
3. Review the macOS CPU-capability abstraction, which currently reports Intel SSE
   capability flags even on ARM, and correct physical-memory reporting.
4. Exercise varied real logs, encodings, rotation/truncation, long lines, dense
   matches, cancellation, file watching, and sleep/wake behavior.
5. Decide whether to retain Qt 6.7.3 temporarily or update Qt and the pinned archive
   dependency together; refresh the older CI configuration.
6. Validate optional crash reporting and all helper binaries before enabling it.
7. Produce a clean release bundle using the project's own signing identity,
   hardened runtime and notarization; test it on a separate Mac without build tools.

The ARM64 feasibility question is resolved positively. Broad OS compatibility,
release packaging, and representative performance validation remain separate work.

## Installer workflow follow-up — 2026-09-23

Added `.github/workflows/macos-pkg.yml` and `scripts/package-macos.sh` to build
an unsigned installer from `master` without Apple credentials. The app inside is
ad-hoc signed. The workflow selects macOS 15 ARM runners, Qt 6.7.3, a macOS 14
deployment target, and a generic ARMv8 baseline. `KLOGG_GENERIC_CPU` now honors
that baseline on native ARM hosts; host-versus-target detection is otherwise
unchanged.

Local validation with those deployment/CPU settings passed all three CTest
targets in 12.74 seconds. Actionlint, ShellCheck, and `git diff --check` passed.
The packaging script created `build_root/pkg-validation/klogg-24.11.0.1-mac-arm64.pkg`.
The extracted package was checked for macOS 14 and ARM64 installer requirements,
the fixed `/Applications/klogg.app` destination, non-relocatable replacement of
the app, valid ad-hoc signatures, 20 Mach-O files containing ARM64, and a matching
SHA-256 checksum. The packaged app's version smoke test passed without external
Qt plugin/library environment overrides.

This verifies construction and payload integrity, not installation on macOS 14:
the local build/tests still ran on macOS 27. GitHub-hosted execution, an actual
installation/upgrade, and testing on the oldest supported OS remain unverified.
No workflow was pushed or dispatched during local validation. See
[installer instructions](BUILD.md#github-actions-installer-from-master).
