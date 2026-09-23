# How to Build Klogg

## Overview

These instructions will get you a copy of the project up and running on your local machine for development and testing purposes.
Local builds can be faster because code can be optimized for current CPU instead of generic x86-64. Support for SSE4/AVX code paths
will be enabled if available on build machine.

## Getting the Source

This project is [hosted on GitHub](https://github.com/variar/klogg). You can clone this project directly using this command:

```
git clone https://github.com/variar/klogg
```

## Dependencies

To build Klogg:

- cmake 3.12 or later to generate build files
- C++ compiler with decent C++17 support (at least gcc 7.5, clang 7, msvc 19.14)
- Qt libraries 5.9 or later (CI builds use Qt 5.9.5/5.12.5/5.15.2):
  - QtCore
  - QtGui
  - QtWidgets
  - QtConcurrent
  - QtNetwork
  - QtXml
  - QtTools

To build Hyperscan regular expressions backend (default):

- CPU with support for [SSSE3](https://en.wikipedia.org/wiki/SSSE3) instructions (for Hyperscan backend)
- Boost (1.58 or later, header-only part)
- Ragel (6.8 or later; precompiled binary is provided for Windows; has to be installed from package managers on Linux or Homebrew on Mac)

To build installer for Windows:

- nsis to build installer for Windows
- Precompiled OpenSSl library to enable https support on Windows

Building tests:

- QtTest

All other dependencies are provided by [CPM](https://github.com/cpm-cmake/CPM.cmake) during cmake configuration stage (see 3rdparty directory).

CPM will try to find Hyperscan, TBB, uchardet and xxhash installed on build host.
If a library can't be found, the one provided by CPM will be used.

## Building

### Configuration options

By default Klogg is built without support for reporting crash dumps. This can be enabled via cmake option `-DKLOGG_USE_SENTRY=ON`.

Klogg uses Hyperscan regular expressions library which requires CPU with SSSE3 support, ragel and boost headers.
Klogg can be built with only Qt reqular expressions backend by passing `-DKLOGG_USE_HYPERSCAN=OFF` to cmake.

Klogg can use custom memory allocator. By default it uses TBB memory allocator for Windows, mimalloc on Linux and default system allocator on MacOS.
Memory allocator override can be turned off by passing `-DKLOGG_OVERRIDE_MALLOC`. If you want to use TBB allocator on Linux then pass
`-DKLOGG_USE_MIMALLOC=OFF`.

### Building on Linux

Here is how to build klogg on Ubuntu 18.04.

Install dependencies:

```
sudo apt-get install build-essential cmake qtbase5-dev libboost-all-dev ragel
```

Configure and build klogg:

```
cd <path_to_klogg_repository_clone>
mkdir build_root
cd build_root
cmake -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
cmake --build .
```

**_If cmake gives error about missing "Qt5LinguistTools" configuration files, try running:_**

```bash
sudo apt-get install qttools5-dev
```

Binaries are placed into `build_root/output`.

See `.github/workflows/ci-build.yml` for more information on build process.

### Building on Windows

Install Microsoft Visual Studio 2017 or 2019 with C++ support.
Community edition can be downloaded from [Microsoft](https://visualstudio.microsoft.com/vs/).

Intall latest Qt version using [online installer](https://www.qt.io/download-qt-installer).
Make sure to select version matching Visual Studio installation. 64-bit libraries are recommended.

Install CMake from [Kitware](https://cmake.org/download/).
Use version 3.14 or later for Visual Studio 2019 support.

Download the Boost source code from http://www.boost.org/users/download/.
Extract to some folder. Directory structure should be something like `C:\Boost\boost_1_63_0`.
Then add `BOOST_ROOT` environment variable pointing to main directory of Boost sources so CMake is able to fine it.

Prepare build environment for CMake. Open command prompt window and depending on version of Visual Studio run either

```
call "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\Common7\Tools\vsdevcmd" -arch=x64
```

or

```
call "%ProgramFiles(x86)%\Microsoft Visual Studio\2017\Community\Common7\Tools\vsdevcmd" -arch=x64
```

Next setup Qt paths:

```
<path_to_qt_installation>\bin\qtenv2.bat
```

Then add CMake to PATH:

```
set PATH=<path_to_cmake_bin>:$PATH
```

Configure klogg solution (use CMake generator matching Visual Studio version):

```
cd <path_to_project_root>
md build_root
cd build_root
cmake -G "Visual Studio 16 2019 Win64" -DCMAKE_BUILD_TYPE=RelWithDebInfo ..
```

CMake should generate `klogg.sln` file in `<path_to_project_root>\build_root` directory. Open solution and build it.

Binaries are placed into `build_root/output`.

For https network urls support download precompiled openssl library https://mirror.firedaemon.com/OpenSSL/openssl-1.1.1l-dev.zip.
Put libcrypto-1_1 and libssl-1_1 for desired architecture near klogg binaries.

### Building on Mac OS

Klogg requires macOS High Sierra (10.13) or higher.

Install [Homebrew](https://brew.sh/) using terminal:

```
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
```

Homebrew installer should also install xcode command line tools.

Download and install build dependencies:

```
brew install cmake ninja qt boost ragel
```

Usually path to qt installation looks like `/usr/local/Cellar/qt/5.14.0/lib/cmake/Qt5`

Configure and build klogg:

```
cd <path_to_klogg_repository_clone>
mkdir build_root
cd build_root
cmake -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DQt5_DIR=<path_to_qt_install> ..
cmake --build .
```

Binaries are placed into `build_root/output`.

By default, klogg will rely on cmake to figure out target MacOS version. Usually it uses build host version.
To override default cmake value pass an option `-DKLOGG_OSX_DEPLOYMENT_TARGET=<target>` to cmake during configuration step,
`<target>` is one of `10.14`, `10.15`, `11`, `12`. Klogg's traget must be greater or equal to target used by Qt libraries.

### Apple Silicon validation build

The native ARM64 configuration was validated with Qt 6.7.3, including Core5Compat,
Vectorscan enabled, and the default system allocator. Use the CI-pinned Qt version:
the pinned archive dependency does not compile unchanged with Qt 6.11.2.
Install CMake, Ninja, Boost, and Ragel, then install Qt 6.7.3 for macOS with the
Qt installer or `aqtinstall`. An isolated installation can be made from the repository root:

```sh
brew install cmake ninja boost ragel
python3 -m venv build_root/aqt-env
build_root/aqt-env/bin/pip install aqtinstall
build_root/aqt-env/bin/aqt install-qt mac desktop 6.7.3 clang_64 \
  -O build_root/qt --modules qt5compat \
  --archives qtbase qttools qtsvg qtimageformats qttranslations

cmake -S . -B build_root -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_PREFIX_PATH="$PWD/build_root/qt/6.7.3/macos" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DKLOGG_USE_VECTORSCAN=ON -DKLOGG_USE_HYPERSCAN=OFF \
  -DKLOGG_USE_SENTRY=OFF -DKLOGG_OVERRIDE_MALLOC=OFF \
  -DKLOGG_BUILD_TESTS=ON
cmake --build build_root --target ci_build --parallel 6
ctest --test-dir build_root --output-on-failure
file build_root/output/klogg.app/Contents/MacOS/klogg
```

Use a fresh build directory when switching Qt versions. CMake 4 needs the policy
compatibility argument for older dependencies. Qt tools must be able to query CPU
capabilities; restricted environments can incorrectly report missing NEON support.

This command builds for the local Mac, using the current SDK's default deployment
target and the existing `-march=native` policy. It is not a portable release recipe.
Set and validate an explicit deployment target and CPU baseline before distribution.
See [Apple Silicon validation results](APPLE_SILICON_VALIDATION.md) for the measured
results, local app location, and remaining release work.

### GitHub Actions installer from master

The **Build Apple Silicon installer** workflow (`.github/workflows/macos-pkg.yml`)
runs on pushes to `master` and supports **Actions → Build Apple Silicon installer →
Run workflow**. Manual runs also check out `master`, regardless of the selected
workflow branch. Merge the workflow into the default branch (`master`) for
GitHub's manual-run button to appear.

The job builds and tests ARM64 with Qt 6.7.3 on a macOS 15 runner, using a generic
ARMv8 CPU baseline and a macOS 14 deployment target. Download
`klogg-macos-arm64-pkg-<run number>` from the run's **Artifacts** section. It contains
`klogg-<version>-mac-arm64.pkg` and its SHA-256 checksum, retained for 30 days.

The installer requires Apple Silicon and macOS 14+, installs
`/Applications/klogg.app`, and replaces an existing klogg bundle at that location.
It does not search for or overwrite copies elsewhere. The app is ad-hoc signed;
the `.pkg` is unsigned and not notarized. No Apple developer credentials or
repository secrets are required. Downloaded installers may require explicit
approval in macOS Privacy & Security. The workflow uploads build artifacts; it
does not publish a GitHub Release.

To package an existing local build using the same script:

```sh
MACDEPLOYQT="$PWD/build_root/qt/6.7.3/macos/bin/macdeployqt" \
  bash scripts/package-macos.sh build_root build_root/packages
```

The local script derives the installer's minimum macOS version from the executable,
so an older macOS 27 prototype remains a macOS 27 package. To create a macOS 14
package, configure with `-DCMAKE_OSX_DEPLOYMENT_TARGET=14.0` and
`-DKLOGG_GENERIC_CPU=ON` and rebuild first. `PKG_VERSION` can optionally override
the numeric package version; CI appends its run number to the app's version.

## Running tests

Tests are built by default. To turn them off pass `-DKLOGG_BUILD_TESTS:BOOL=OFF` to cmake.
Tests use catch2 (bundled with klogg sources) and require Qt5Test module. Tests can be run using ctest tool provider by CMake:

```
cd <path_to_klogg_repository_clone>
cd build_root
ctest --build-config RelWithDebInfo --verbose
```
