# vision-pack

AMD ROCm Computer Vision package aggregator. Builds and packages
[MIVisionX](https://github.com/ROCm/MIVisionX),
[rocAL](https://github.com/ROCm/rocAL),
[rocCV](https://github.com/ROCm/rocCV), and
[rocPyDecode](https://github.com/ROCm/rocPyDecode)
from a single repository against a ROCm SDK base.

Modelled on [TheRock](https://github.com/ROCm/TheRock): each component is an
independent ExternalProject that builds and stages in parallel where possible,
with stamp-file ordering enforcing dependencies.

---

## Build graph

```
ROCm SDK (/opt/rocm)
    │
    ├── mivisionx      ─┐
    ├── rocCV          ─┤  (parallel — no inter-library deps)
    └── rocpydecode    ─┘
         │
    [protobuf + libjpeg-turbo]  (parallel with above, rocAL prerequisites)
         │
       rocal            (depends on mivisionx stage + bundled deps)
```

---

## Repository layout

```
vision-pack/
├── CMakeLists.txt                  top-level orchestrator
├── cmake/
│   ├── vision_pack_subproject.cmake   ExternalProject orchestration
│   └── vision_pack_bundled_dep.cmake  bundled dep helper macros
│
├── mivisionx/      → ROCm/MIVisionX@develop
├── rocal/          → ROCm/rocAL@develop
├── rocCV/          → ROCm/rocCV@develop
├── rocpydecode/    → ROCm/rocPyDecode@develop
│
└── third-party/
    ├── pybind11/       v3.1.0   (build-time only)
    ├── dlpack/         v1.3     (build-time only)
    ├── protobuf/       v3.21.12 (ships with rocAL — last 3.x without abseil dep)
    ├── libjpeg-turbo/  3.2.0    (ships with rocAL)
    └── rapidjson/      master   (build-time only; v1.1.0 incompatible with rocAL)
```

---

## Prerequisites

### ROCm SDK

Install ROCm 10.1 or later. The nightly SDK from Quartz is used for
development builds:

```bash
# Add Quartz nightly deb repo (adjust date to latest available)
echo 'deb [arch=amd64 trusted=yes] https://rocm.nightlies.amd.com/packages-multi-arch/deb/20260822-32539019050 stable main' \
    | sudo tee /etc/apt/sources.list.d/rocm-nightly.list
sudo apt-get update
```

### System packages (Ubuntu 22.04 / 24.04)

```bash
sudo apt-get install -y \
    cmake \
    ninja-build \
    python3-dev \
    libturbojpeg0-dev \
    liblmdb-dev \
    libsndfile1-dev \
    libavcodec-dev \
    libavformat-dev \
    libavutil-dev \
    libswscale-dev \
    libtar-dev
```

### ROCm computer vision packages

```bash
# amdrocm-decode-dev:  rocdecode headers and cmake config
# amdrocm-decode-test: rocdecode utility sources (rocvideodecode/, resize_kernels.cpp)
#                      required at build time by rocAL and rocPyDecode
sudo apt-get install -y amdrocm-decode-dev amdrocm-decode-test

# amdrocm-jpeg-dev: rocJPEG headers (required by rocAL)
sudo apt-get install -y amdrocm-jpeg-dev
```

> **Note:** The versioned variants (`amdrocm-decode-dev10.1`, `amdrocm-jpeg-dev10.1`) also
> work and may be preferred when pinning to a specific ROCm release.

> **Note:** rpp (ROCm Performance Primitives) is required by MIVisionX.
> It is included in the ROCm 10.1 SDK install. Verify with:
> `ls /opt/rocm/include/rpp/rpp.h`

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
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/opt/rocm

cmake --build . --parallel $(nproc)
```

### Component enable flags

All four libraries are ON by default. Disable individually:

```bash
cmake .. \
    -DVISION_PACK_ENABLE_MIVISIONX=OFF \
    -DVISION_PACK_ENABLE_ROCAL=OFF \
    -DVISION_PACK_ENABLE_ROCCV=OFF \
    -DVISION_PACK_ENABLE_ROCPYDECODE=OFF
```

> **Note:** Disabling rocAL also disables building bundled protobuf and
> libjpeg-turbo (`VISION_PACK_BUNDLE_PROTOBUF`, `VISION_PACK_BUNDLE_TURBOJPEG`
> are automatically OFF when `VISION_PACK_ENABLE_ROCAL=OFF`).

### Bundled dependency flags

By default all third-party deps are built from source. Override to use
system-installed versions (e.g. for distro packaging):

```bash
cmake .. \
    -DVISION_PACK_BUNDLE_PYBIND11=OFF \
    -DVISION_PACK_BUNDLE_DLPACK=OFF \
    -DVISION_PACK_BUNDLE_PROTOBUF=OFF \
    -DVISION_PACK_BUNDLE_TURBOJPEG=OFF \
    -DVISION_PACK_BUNDLE_RAPIDJSON=OFF
```

---

## Install

```bash
# Installs to CMAKE_INSTALL_PREFIX (default /opt/rocm)
sudo cmake --install build
```

### Install layout

```
/opt/rocm/
├── lib/
│   ├── libopenvx.so.1          MIVisionX OpenVX runtime
│   ├── libvxu.so.1             MIVisionX VXU utilities
│   ├── libvx_rpp.so.1          MIVisionX RPP extension
│   ├── librocal.so.2           rocAL data loading library
│   ├── rocal_pybind.*.so       rocAL Python bindings
│   ├── libroccv.so.0           rocCV GPU image processing
│   ├── rocpycv.*.so            rocCV Python bindings
│   ├── rocpydecode.*.so        rocPyDecode video decode Python
│   └── rocpyjpegdecode.*.so    rocPyDecode JPEG decode Python
├── include/
│   ├── mivisionx/              OpenVX + AMD extension headers
│   ├── rocal/                  rocAL C++ API headers
│   └── roccv/                  rocCV C++ API headers
└── share/
    ├── mivisionx/              samples, test data
    ├── rocal/                  test scripts
    ├── roccv/                  samples, test data
    ├── rocpyjpegdecode/        samples
    └── rocpydecode/            samples
```

---

## Test

Each component installs CTest suites. Run after install:

```bash
# Run all ctests from build directory
cd build
ctest --output-on-failure --parallel $(nproc)

# Or per-component
ctest -R mivisionx --output-on-failure
ctest -R rocal --output-on-failure
ctest -R roccv --output-on-failure
ctest -R rocpydecode --output-on-failure
```

---

## Third-party dependency notes

| Dep | Version | License | Shipped? | Why bundled |
|---|---|---|---|---|
| pybind11 | v3.1.0 | BSD-3 | No | build-time only; compiled into .so |
| dlpack | v1.3 | Apache-2.0 | No | build-time only; header-only |
| protobuf | v3.21.12 | BSD-3 | Yes | rocAL links `libprotobuf.so` dynamically; v3.22+ requires abseil nested submodule |
| libjpeg-turbo | 3.2.0 | BSD/IJG | Yes | rocAL links `libturbojpeg.so` dynamically |
| rapidjson | master | MIT | No | header-only, compiled into librocal.so; v1.1.0 missing API required by rocAL |

---

## Known issues

- **MIVisionX cmake exports missing** — MIVisionX does not install
  `MIVisionXConfig.cmake`. Downstream consumers must use `FindMIVisionX.cmake`.
  Tracked: [MIVisionX#1761](https://github.com/ROCm/MIVisionX/issues/1761)

- **rocAL cmake exports missing** — rocAL does not install `rocalConfig.cmake`.
  Tracked: [rocAL#514](https://github.com/ROCm/rocAL/issues/514)

- **Python bindings install to lib/ instead of site-packages** — rocAL and
  rocPyDecode install `.so` extension modules to `/opt/rocm/lib/` rather than
  the Python site-packages directory, requiring manual `PYTHONPATH` adjustment.
  Tracked: [rocAL#514](https://github.com/ROCm/rocAL/issues/514),
  [rocPyDecode#285](https://github.com/ROCm/rocPyDecode/issues/285)

- **rocPyDecode no COMPONENT grouping** — install directives lack runtime/dev/test
  separation, making CPack component packaging impossible.
  Tracked: [rocPyDecode#285](https://github.com/ROCm/rocPyDecode/issues/285)

- **WebDataset reader disabled** — rocAL's WebDataset reader requires `libtar`,
  which is not installed by default. Install `libtar-dev` to enable it.

---

## Tested configuration

| Component | Version |
|---|---|
| OS | Ubuntu 24.04 LTS |
| ROCm | 10.1.0 (nightly 20260805) |
| GPU | gfx1100 (Radeon RX 7900) |
| CMake | 3.28.3 |
| Compiler | AMD clang 23.0.0 (amdclang++) |
| Python | 3.12.3 |
