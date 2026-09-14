# vision-pack

AMD ROCm Computer Vision optional extension pack. Builds and packages
[MIVisionX](https://github.com/ROCm/MIVisionX),
[rocAL](https://github.com/ROCm/rocAL),
[rocCV](https://github.com/ROCm/rocCV), and
[rocPyDecode](https://github.com/ROCm/rocPyDecode)
from a single repository, installing seamlessly into an existing `/opt/rocm`
tree alongside all other ROCm components.

Modelled on [TheRock](https://github.com/ROCm/TheRock): each component builds
as an independent ExternalProject with stamp-file ordering enforcing
dependencies. Bundled runtime deps install into `lib/rocm_sysdeps/lib/`
following the same pattern as ROCm's own sysdeps (zlib, bzip2, liblzma, ...).

---

## Build graph

```
Quartz nightly ROCm SDK (/opt/rocm)
  │  includes: HIP, RPP, rocDecode, rocJPEG, OpenMP, half, rocm_sysdeps
  │
  ├─────────────────────────────────────────────────┐
  │                                                 │
  ├── mivisionx          ──┐                        │  Third-party runtime deps
  ├── rocCV              ──┤  parallel              │  (bundled, ships in
  └── rocpydecode        ──┘  (no inter-lib deps)   │  lib/rocm_sysdeps/lib/)
                                                    │
  ┌─── protobuf          ──┐                        │  ├── libturbojpeg  3.2.0
  ├─── libjpeg-turbo     ──┤  parallel with above   │  ├── libprotobuf  3.21.12
  ├─── liblmdb           ──┤  (rocAL prerequisites) │  ├── liblmdb      1.0.1
  └─── libsndfile        ──┘                        │  └── libsndfile   1.2.2
         │
       rocal    (waits for: mivisionx stage
                            + all bundled deps)

Build-time only (not shipped):
  pybind11 v3.1.0 · dlpack v1.3 · rapidjson master
```

---

## Repository layout

```
vision-pack/
├── CMakeLists.txt                      top-level orchestrator
├── cmake/
│   ├── vision_pack_subproject.cmake    ExternalProject build orchestration
│   └── vision_pack_bundled_dep.cmake   helper macros for bundled deps
├── build_tools/
│   └── fetch_rocm_sdk.py               download Quartz nightly SDK tarball
├── packaging/
│   ├── CMakeLists.txt                  CPack config (DEB/RPM/TGZ)
│   └── meta/amdrocm-vision.control.in  meta-package template
├── .github/workflows/
│   ├── ci.yml                          build + test (manylinux_2_28)
│   └── package.yml                     CPack → DEB/RPM/TGZ + GitHub release
│
├── mivisionx/      → ROCm/MIVisionX@develop
├── rocal/          → ROCm/rocAL@develop
├── rocCV/          → ROCm/rocCV@develop
├── rocpydecode/    → ROCm/rocPyDecode@develop
│
└── third-party/
    ├── pybind11/       v3.1.0    build-time only (compiled into .so)
    ├── dlpack/         v1.3      build-time only (header-only)
    ├── rapidjson/      master    build-time only (compiled into librocal.so)
    ├── protobuf/       v3.21.12  runtime — ships in lib/rocm_sysdeps/lib/
    ├── libjpeg-turbo/  3.2.0     runtime — ships in lib/rocm_sysdeps/lib/
    ├── lmdb/           1.0.1     runtime — ships in lib/rocm_sysdeps/lib/
    └── libsndfile/     1.2.2     runtime — ships in lib/rocm_sysdeps/lib/
```

---

## Prerequisites

### ROCm SDK

Install ROCm 10.1 or later. The nightly SDK from Quartz is used for CI builds.
For local development on Ubuntu 22.04/24.04:

```bash
# Add Quartz nightly deb repo (replace date with latest available)
echo 'deb [arch=amd64 trusted=yes] https://rocm.nightlies.amd.com/packages-multi-arch/deb/20260822-32539019050 stable main' \
    | sudo tee /etc/apt/sources.list.d/rocm-nightly.list
sudo apt-get update
```

### ROCm computer vision packages

These packages provide headers, cmake configs, and utility sources required
at build time by the vision libraries. They are part of the ROCm distribution
and install into `/opt/rocm` alongside the SDK.

```bash
# rpp — ROCm Performance Primitives (required by MIVisionX)
sudo apt-get install -y amdrocm-rpp amdrocm-rpp-dev amdrocm-rpp-test

# rocdecode — GPU video decode (required by rocAL and rocPyDecode)
# amdrocm-decode-test provides share/rocdecode/utils/ utility sources
# needed at build time
sudo apt-get install -y amdrocm-decode-dev amdrocm-decode-test

# rocjpeg — GPU JPEG decode (required by rocAL)
sudo apt-get install -y amdrocm-jpeg-dev amdrocm-jpeg-test
```

### System build tools (Ubuntu 22.04 / 24.04)

Only build-time tools are required from the OS package manager. All runtime
dependencies (libturbojpeg, libprotobuf, liblmdb, libsndfile) are built from
source in `third-party/` and bundled into `lib/rocm_sysdeps/lib/`.
ffmpeg and OpenCV are excluded by design.

```bash
sudo apt-get install -y cmake ninja-build python3-dev make
```

---

## Clone

```bash
git clone --recurse-submodules https://github.com/ROCm/vision-pack.git
cd vision-pack
```

Or if already cloned:

```bash
git submodule update --init --recursive
```

---

## Build

```bash
mkdir build && cd build

cmake .. \
    -DROCM_PATH=/opt/rocm \
    -DCMAKE_BUILD_TYPE=Release

cmake --build . --parallel $(nproc)
```

`CMAKE_INSTALL_PREFIX` defaults to `ROCM_PATH` (`/opt/rocm`) so the install
step drops files directly into the ROCm tree.

### Component enable flags

All four libraries are ON by default. Disable individually:

```bash
cmake .. \
    -DVISION_PACK_ENABLE_MIVISIONX=OFF \
    -DVISION_PACK_ENABLE_ROCAL=OFF \
    -DVISION_PACK_ENABLE_ROCCV=OFF \
    -DVISION_PACK_ENABLE_ROCPYDECODE=OFF
```

> Disabling rocAL automatically disables its bundled runtime deps
> (protobuf, turbojpeg, lmdb, libsndfile).

### Bundled dependency flags

By default all deps are built from source. Set to OFF to use system-installed
versions (useful for distro package builds):

```bash
cmake .. \
    -DVISION_PACK_BUNDLE_PYBIND11=OFF \
    -DVISION_PACK_BUNDLE_DLPACK=OFF \
    -DVISION_PACK_BUNDLE_RAPIDJSON=OFF \
    -DVISION_PACK_BUNDLE_PROTOBUF=OFF \
    -DVISION_PACK_BUNDLE_TURBOJPEG=OFF \
    -DVISION_PACK_BUNDLE_LMDB=OFF \
    -DVISION_PACK_BUNDLE_LIBSNDFILE=OFF
```

---

## Install

```bash
# Installs into /opt/rocm — same as any other ROCm component
sudo cmake --install build
```

### Install layout

vision-pack installs directly into `/opt/rocm` with no new top-level
directories — identical conventions to every other ROCm component.

```
/opt/rocm/
├── lib/
│   ├── libopenvx.so.1, libvxu.so.1, libvx_rpp.so.1    MIVisionX
│   ├── librocal.so.2, rocal_pybind.*.so                 rocAL + Python bindings
│   ├── libroccv.so.0, rocpycv.*.so, rocpycv.pyi         rocCV + Python bindings
│   ├── rocpydecode.*.so, rocpyjpegdecode.*.so            rocPyDecode
│   ├── cmake/
│   │   └── roccv/                   cmake package config (rocCV)
│   └── rocm_sysdeps/lib/            bundled runtime deps — same dir as
│       ├── libturbojpeg.so*          ROCm's zlib, bzip2, liblzma, libdrm ...
│       ├── libprotobuf.so*
│       ├── liblmdb.so*
│       └── libsndfile.so*
├── include/
│   ├── mivisionx/                   OpenVX + AMD extension headers
│   ├── rocal/                       rocAL C++ API headers
│   └── roccv/                       rocCV C++ API headers
├── bin/
│   └── runvx                        MIVisionX graph execution tool
└── share/
    ├── mivisionx/                   samples, test data
    ├── rocal/                       test scripts
    ├── roccv/                       samples, test data
    └── rocpydecode/                 samples
```

All vision `.so` files have `$ORIGIN:$ORIGIN/../lib/rocm_sysdeps/lib` baked
into their RPATH so bundled deps (and ROCm's existing sysdeps) are found at
runtime without setting `LD_LIBRARY_PATH`.

---

## Test

```bash
cd build

# rocPyDecode — fully self-contained, always runnable
ctest --output-on-failure -R rocpydecode

# MIVisionX — runvx-based GDF tests (no GPU required)
ctest --output-on-failure -R "openvx_gdf_tests|openvx_vision_coverage"

# rocCV — enable tests at configure time with -DFULL_BUILD=ON
ctest --output-on-failure -R roccv

# rocAL — requires rocAL installed to ROCM_PATH before running
# (test CMake builds from source and searches ROCM_PATH for headers)
ctest --output-on-failure -R rocal
```

---

## Third-party dependencies

| Dep | Version | License | Installed to | Notes |
|---|---|---|---|---|
| pybind11 | v3.1.0 | BSD-3 | — (build-time) | compiled into .so, not shipped |
| dlpack | v1.3 | Apache-2.0 | — (build-time) | header-only, not shipped |
| rapidjson | master | MIT | — (build-time) | compiled into librocal.so; v1.1.0 missing API needed by rocAL |
| protobuf | v3.21.12 | BSD-3 | `lib/rocm_sysdeps/lib/` | v3.22+ requires abseil nested submodule |
| libjpeg-turbo | 3.2.0 | BSD/IJG | `lib/rocm_sysdeps/lib/` | rocAL links libturbojpeg.so dynamically |
| lmdb | 1.0.1 | OpenLDAP | `lib/rocm_sysdeps/lib/` | rocAL Caffe/Caffe2 LMDB reader |
| libsndfile | 1.2.2 | LGPL-2.1 | `lib/rocm_sysdeps/lib/` | rocAL audio augmentation; built without external codecs |

**Excluded by design:** ffmpeg (libavcodec/avformat/avutil/swscale) and OpenCV.
rocAL is built with `-DBUILD_WITH_FFMPEG=OFF -DBUILD_WITH_OPENCV=OFF` to keep
the dependency tree self-contained.

---

## Package output

The `package.yml` CI workflow produces:

| Package | Contents |
|---|---|
| `amdrocm-mivisionx` | libopenvx, libvxu, libvx_rpp, runvx |
| `amdrocm-mivisionx-devel` | headers, cmake config, samples |
| `amdrocm-rocal` | librocal, rocal_pybind Python binding |
| `amdrocm-rocal-devel` | headers |
| `amdrocm-roccv` | libroccv, rocpycv Python binding |
| `amdrocm-roccv-devel` | headers, cmake config |
| `amdrocm-rocpydecode` | rocpydecode + rocpyjpegdecode Python bindings |
| `amdrocm-vision-sysdeps` | libturbojpeg, libprotobuf, liblmdb, libsndfile |
| `amdrocm-vision` | meta — pulls in all runtime components |
| `amdrocm-vision-sdk` | meta — runtime + all dev headers |
| `amdrocm-vision-tests` | meta — sdk + all test suites |

---

## Known issues

- **MIVisionX cmake exports missing** — no `MIVisionXConfig.cmake` installed;
  downstream consumers use `FindMIVisionX.cmake`.
  [MIVisionX#1761](https://github.com/ROCm/MIVisionX/issues/1761)

- **rocAL cmake exports missing** — no `rocalConfig.cmake` installed.
  [rocAL#514](https://github.com/ROCm/rocAL/issues/514)

- **Python bindings in lib/ instead of site-packages** — rocAL and rocPyDecode
  install `.so` extension modules to `lib/` requiring manual `PYTHONPATH` setup.
  [rocAL#514](https://github.com/ROCm/rocAL/issues/514),
  [rocPyDecode#285](https://github.com/ROCm/rocPyDecode/issues/285)

- **rocPyDecode no COMPONENT grouping** — all install() directives lack
  runtime/dev/test separation, breaking CPack component splits.
  [rocPyDecode#285](https://github.com/ROCm/rocPyDecode/issues/285)

- **rocAL WebDataset reader disabled** — requires libtar, excluded to keep
  the build self-contained.

- **rocAL ffmpeg reader disabled** — requires libavcodec/avformat chain,
  excluded by design (`-DBUILD_WITH_FFMPEG=OFF`).

---

## Tested configuration

| | |
|---|---|
| OS | Ubuntu 24.04 LTS |
| ROCm | 10.1.0 (nightly 20260805) |
| GPU | gfx1100 (Radeon RX 7900 series) |
| CMake | 3.28.3 |
| Compiler | AMD clang 23.0.0 (`amdclang++`) |
| Python | 3.12.3 |
| MIVisionX | 4.0.0 |
| rocAL | 2.5.0 |
| rocCV | 0.4.0 |
| rocPyDecode | 1.0.0 |
