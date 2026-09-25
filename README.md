# vision-pack

Builds and packages four AMD ROCm computer-vision libraries as an extension
on a **pre-built** ROCm SDK. The product is DEB, RPM, and a dist tarball that
install into `/opt/rocm`. It does not build ROCm itself.

| Library | Package | Ships |
|---|---|---|
| [MIVisionX](https://github.com/ROCm/MIVisionX) | `amdrocm-mivisionx` | `libopenvx`, `libvxu`, `libvx_rpp`, `runvx` |
| [rocAL](https://github.com/ROCm/rocAL) | `amdrocm-rocal` | `librocal`, `rocal_pybind` |
| [rocCV](https://github.com/ROCm/rocCV) | `amdrocm-roccv` | `libroccv`, `rocpycv` |
| [rocPyDecode](https://github.com/ROCm/rocPyDecode) | `amdrocm-pydecode` | `rocpydecode`, `rocpyjpegdecode` |

All four runtimes, including `amdrocm-pydecode`, are required. Submodules are
not patched ([ADR 0003](docs/adr/0003-no-submodule-patches.md)). Design notes:
[docs/adr](docs/adr/).

One build covers every GPU: the HIP compiler emits a code object per gfx
target into each `.so`. The SDK family name selects *which SDK to build
against*, not what the libraries contain.

## Build graph

```
ROCm SDK  (HIP, RPP, rocDecode, rocJPEG, OpenMP, rocm_sysdeps)
  │
  ├── mivisionx      ──┐
  ├── roccv          ──┤  parallel, SDK only
  └── rocpydecode    ──┘
                         │
  protobuf               │  parallel with the three above
  libjpeg-turbo          │  (rocAL prerequisites; ship in
  lmdb                   │   lib/rocm_sysdeps/lib/)
  libsndfile             │
         │               │
         └──── rocal ────┘  waits for mivisionx stage + bundled deps

Build-time only (not shipped): pybind11 v3.1.0 · dlpack v1.3 · rapidjson
```

---

## Install

ROCm 10.2+ at `/opt/rocm` (HIP, RPP, rocDecode, rocJPEG).

```bash
# DEB — one invocation satisfies *vision-pack* inter-Depends.
# ROCm packages (hip-runtime-amd, amdrocm-rpp, amdrocm-decode, amdrocm-jpeg)
# must already be installed; otherwise follow with: sudo apt-get install -f
sudo dpkg -i amdrocm-*.deb

# RPM
sudo rpm -i amdrocm-*.rpm

# Tarball (no .pth — set PYTHONPATH)
sudo tar -xzf vision-pack-dist-linux-multiarch-*.tar.gz -C /opt/rocm
export PYTHONPATH=/opt/rocm/lib${PYTHONPATH:+:$PYTHONPATH}
```

Python modules live in `/opt/rocm/lib`. DEB/RPM install a `.pth` for system
Python; a venv or the tarball still needs `PYTHONPATH` (or a copy of the `.pth`).

### Install layout

```
/opt/rocm/
├── bin/
│   └── runvx
├── include/
│   ├── mivisionx/                 OpenVX + AMD extension headers
│   ├── rocal/                     rocAL C++ API headers
│   └── roccv/                     rocCV C++ API headers
├── lib/
│   ├── libopenvx.so*, libvxu.so*, libvx_rpp.so*
│   ├── librocal.so*, rocal_pybind*.so, amd/rocal/
│   ├── libroccv.so*, rocpycv*.so, rocpycv.pyi
│   ├── rocpydecode*.so, rocpyjpegdecode*.so
│   ├── pyRocVideoDecode/, pyRocJpegDecode/
│   ├── cmake/
│   │   ├── FindMIVisionX.cmake    shim (MIVisionX#1761)
│   │   ├── Findrocal.cmake        shim (rocAL#514)
│   │   └── roccv/                 rocCV Config.cmake (-devel / tarball)
│   └── rocm_sysdeps/lib/          next to ROCm's zlib, bzip2, …
│       ├── libturbojpeg-rocm-vision.so*
│       ├── libjpeg-rocm-vision.so*
│       ├── libprotobuf-rocm-vision.so*
│       ├── libprotobuf-lite-rocm-vision.so*
│       ├── liblmdb-rocm-vision.so*
│       └── libsndfile-rocm-vision.so*
└── share/
    ├── mivisionx/                 samples (-devel), test (-test)
    ├── rocal/test/
    ├── roccv/                     samples (-devel), test (-test)
    ├── rocpydecode/               samples, tests
    └── rocpyjpegdecode/           samples, tests
```

The `.pth` is not under `/opt/rocm` and is not in the dist tarball: DEB writes
`/usr/lib/python3/dist-packages/amdrocm-vision.pth`; RPM `%post` writes the
same file into Python's `site-packages`.

RPATH on every vision `.so` is
`$ORIGIN:$ORIGIN/../lib/rocm_sysdeps/lib:$ORIGIN/llvm/lib`, so bundled deps,
ROCm sysdeps, and `libomp.so` resolve with no `LD_LIBRARY_PATH`. Bundled deps
use private `*-rocm-vision` SONAMEs so a host copy cannot shadow them
([ADR 0004](docs/adr/0004-soname-isolation.md)). Isolation is
`build_tools/rewrite_sonames.py` on the staged tree, before CPack.

---

## Package output

| Package | Contents |
|---|---|
| `amdrocm-mivisionx` | libopenvx, libvxu, libvx_rpp, runvx |
| `amdrocm-mivisionx-devel` | headers, FindMIVisionX.cmake, samples |
| `amdrocm-mivisionx-test` | test sources + data |
| `amdrocm-rocal` | librocal, rocal_pybind, `lib/amd/rocal` |
| `amdrocm-rocal-devel` | headers, Findrocal.cmake |
| `amdrocm-rocal-test` | test sources + data |
| `amdrocm-roccv` | libroccv, rocpycv, rocpycv.pyi |
| `amdrocm-roccv-devel` | headers, roccvConfig.cmake, samples |
| `amdrocm-roccv-test` | test sources + data |
| `amdrocm-pydecode` | rocpydecode, rocpyjpegdecode, pyRocVideoDecode, pyRocJpegDecode |
| `amdrocm-pydecode-test` | test sources |
| `amdrocm-vision-sysdeps` | isolated libturbojpeg, libjpeg, libprotobuf, libprotobuf-lite, liblmdb, libsndfile (`-rocm-vision` SONAMEs) |
| `amdrocm-vision-pythonpath` | `.pth` registering `/opt/rocm/lib` |
| `amdrocm-vision` | meta — all runtimes (including pydecode) |
| `amdrocm-vision-sdk` | meta — runtime + devel |
| `amdrocm-vision-tests` | meta — sdk + all `-test` packages |

Nightly CI publishes these plus `vision-pack-dist-linux-multiarch-<ver>.tar.gz`.

---

## Build

CMake ≥ 3.21, Ninja, Python 3.12 headers, and a ROCm 10.2 SDK that includes
rpp, rocDecode, rocJPEG, **and** `share/rocdecode/utils` (`roc_video_dec.cpp`).
CI fetches the `gfx94X-dcgpu-tests` nightly tarball for that. On an existing
`/opt/rocm`, install the rpp / rocDecode / rocJPEG **dev** packages plus
`amdrocm-decode-test` and `amdrocm-jpeg-test` — the utils live in the test
packages, not the dev ones.

```bash
sudo apt-get install -y cmake ninja-build python3-dev make patchelf

git clone --recurse-submodules https://github.com/kiritigowda/vision-pack.git
cd vision-pack
python3 build_tools/fetch_rocm_sdk.py --dest /opt/rocm-nightly   # or --url <tarball>

cmake -B build -S . -GNinja -DROCM_PATH=/opt/rocm-nightly -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel $(nproc)
```

Skip a library with `-DVISION_PACK_ENABLE_<NAME>=OFF` (`MIVISIONX`, `ROCAL`,
`ROCCV`, `ROCPYDECODE`). Use a system dep with
`-DVISION_PACK_BUNDLE_<DEP>=OFF` (`PYBIND11`, `DLPACK`, `RAPIDJSON`,
`PROTOBUF`, `TURBOJPEG`, `LMDB`, `LIBSNDFILE`). Disabling rocAL also drops
its bundled runtime deps.

### Packages from this tree

Stage each library, rewrite bundled SONAMEs, then CPack. Do not use
`cmake --install` on the aggregator — it does not copy the stage trees or run
the rewrite.

```bash
mkdir -p build/staging
for p in mivisionx roccv rocal rocpydecode; do
  cp -a "build/_subprojects/${p}/stage/." build/staging/
done
cmake --install build --prefix build/staging --component runtime
python3 build_tools/rewrite_sonames.py build/staging

cmake -B pkg-build -S packaging \
  -DVISION_PACK_STAGING_DIR="$PWD/build/staging" \
  -DVISION_PACK_VERSION=0.2.0
cmake --build pkg-build --target package
tar -czf vision-pack-dist-linux-multiarch-0.2.0.tar.gz -C build/staging .
```

---

## Test

The aggregator does not register ctest. Each library ships test sources under
`share/<lib>/`; CI unpacks the **dist tarball** into `ROCM_PATH` and builds
those projects. GPU suites skip when `/dev/kfd` is missing.

```bash
tar -xzf vision-pack-dist-linux-multiarch-*.tar.gz -C "$ROCM_PATH"
export PYTHONPATH="$ROCM_PATH/lib${PYTHONPATH:+:$PYTHONPATH}"

cmake -B test-build -S "$ROCM_PATH/share/mivisionx/test" \
  -DROCM_PATH="$ROCM_PATH" -DBACKEND=HIP
cmake --build test-build --parallel
ctest --test-dir test-build --output-on-failure

python3 -c "import rocal_pybind, amd.rocal, rocpycv, rocpydecode, rocpyjpegdecode"
```

| Library | Sources | GPU |
|---|---|---|
| MIVisionX | `share/mivisionx/test` | CPU GDF cases only on a CPU host |
| rocAL | `share/rocal/test` | yes (HIP context even for `*_cpu`) |
| rocCV | `share/roccv/test/cpp` | yes |
| rocPyDecode | `share/rocpydecode/tests` | decode tests yes; `types_test.py` / import no |

---

## Third-party dependencies

| Dep | Version | License | Installed to | Notes |
|---|---|---|---|---|
| pybind11 | v3.1.0 | BSD-3 | — (build-time) | compiled into the Python `.so`s, not shipped |
| dlpack | v1.3 | Apache-2.0 | — (build-time) | header-only, not shipped |
| rapidjson | master | MIT | — (build-time) | compiled into librocal.so; v1.1.0 lacks APIs rocAL needs |
| protobuf | v3.21.12 | BSD-3 | `lib/rocm_sysdeps/lib/` | v3.22+ needs abseil; `protobuf-lite` is also shipped |
| libjpeg-turbo | 3.2.0 | BSD/IJG | `lib/rocm_sysdeps/lib/` | libturbojpeg plus isolated libjpeg (`jpeg_std_error`) |
| lmdb | 1.0.1 | OpenLDAP | `lib/rocm_sysdeps/lib/` | rocAL Caffe/Caffe2 LMDB reader |
| libsndfile | 1.2.2 | LGPL-2.1 | `lib/rocm_sysdeps/lib/` | rocAL audio; built without external codecs |

**Excluded by design:** ffmpeg, OpenCV, and libtar
([ADR 0005](docs/adr/0005-no-ffmpeg-opencv.md)). rocAL would pick ffmpeg/libtar
up via `find_package(... QUIET)`, so the build passes
`-DCMAKE_DISABLE_FIND_PACKAGE_FFmpeg=ON` and `-DCMAKE_DISABLE_FIND_PACKAGE_LibTar=ON`.
OpenCV needs no flag; current rocAL never looks for it.

---

## Repository layout

```
vision-pack/
├── CMakeLists.txt
├── cmake/                         ExternalProject engine, finder shims
├── build_tools/                   fetch_rocm_sdk.py, rewrite_sonames.py, …
├── packaging/                     CPack (DEB/RPM/TGZ) + meta-packages
├── .github/workflows/             build.yml → package.yml → test
├── mivisionx/                     ROCm/MIVisionX@develop
├── rocal/                         ROCm/rocAL@develop
├── roccv/                         ROCm/rocCV@develop
├── rocpydecode/                   ROCm/rocPyDecode@develop
└── third-party/                   bundled deps (see table above)
```

---

## Known issues

Workarounds live in vision-pack, not in the submodules.

- No upstream CMake configs: [MIVisionX#1761](https://github.com/ROCm/MIVisionX/issues/1761),
  [rocAL#514](https://github.com/ROCm/rocAL/issues/514) — shims in `lib/cmake`.
- Python extensions install to `lib/` not site-packages:
  [rocAL#514](https://github.com/ROCm/rocAL/issues/514),
  [rocPyDecode#285](https://github.com/ROCm/rocPyDecode/issues/285).
- rocPyDecode `find_package(Python3 Development)` needs `libpython.so` (CI
  forwards `Python3_ROOT_DIR` to shared CPython):
  [rocPyDecode#290](https://github.com/ROCm/rocPyDecode/issues/290).
- rocPyDecode install rules have no COMPONENT tags
  ([rocPyDecode#285](https://github.com/ROCm/rocPyDecode/issues/285));
  packaging splits by path.
- rocAL / libjpeg-turbo RPATH and libjpeg `NEEDED` repairs are in
  `rewrite_sonames.py` ([#39](https://github.com/kiritigowda/vision-pack/issues/39),
  [#43](https://github.com/kiritigowda/vision-pack/issues/43),
  [#45](https://github.com/kiritigowda/vision-pack/issues/45)).

---

## Tested configuration

CI builds in manylinux_2_28 (CPU). GPU suites skip without `/dev/kfd`.

| | |
|---|---|
| OS | Ubuntu 24.04 LTS (local), manylinux_2_28 (CI) |
| ROCm | 10.2 (nightly `gfx94X-dcgpu-tests`) |
| GPU | gfx1100 when present (Radeon RX 7900 series) |
| CMake | 3.28 |
| Compiler | AMD clang (`amdclang++`) |
| Python | 3.12 |

[CHANGELOG](CHANGELOG.md) · [MIT License](LICENSE)
