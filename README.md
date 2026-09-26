# vision-pack

AMD ROCm Computer Vision optional extension pack. Builds and packages
[MIVisionX](https://github.com/ROCm/MIVisionX),
[rocAL](https://github.com/ROCm/rocAL),
[rocCV](https://github.com/ROCm/rocCV), and
[rocPyDecode](https://github.com/ROCm/rocPyDecode)
from a single repository, installing into an existing `/opt/rocm` tree
alongside every other ROCm component.

Modelled on [TheRock](https://github.com/ROCm/TheRock): each library builds as
an independent ExternalProject with stamp-file ordering. Bundled runtime deps
install into `lib/rocm_sysdeps/lib/`, the same directory ROCm already uses for
zlib, bzip2, liblzma, and the rest.

The **product** is the `amdrocm-*` DEB/RPM set plus
`vision-pack-dist-linux-multiarch-<ver>.tar.gz`. All four runtimes — including
`amdrocm-pydecode` — are required. Submodules are not patched
([ADR 0003](docs/adr/0003-no-submodule-patches.md)).

**One build, every architecture.** The vision libraries contain GPU kernels,
but they never need a per-architecture rebuild. HIP emits a code object per
gfx target and bundles them into a fat binary inside each `.so`, so one pass
produces artifacts that run everywhere — that is what `multiarch` in the
artifact names means. There is no per-architecture matrix. The GPU family in
an SDK tarball name selects *which SDK to build against*, not what the build
emits.

The architecture list is the ROCm compiler default — vision-pack sets no
`AMDGPU_TARGETS` or `--offload-arch`. Built against ROCm 10.2, `libopenvx`,
`libvx_rpp` and `librocal` each carry 17 code objects (gfx908, gfx90a, gfx942,
gfx950, gfx1030–1032, gfx1100–1102, gfx1150–1153, gfx1200/1201, gfx1250), while
`libroccv` carries 13 — it is missing gfx1150, gfx1152, gfx1153 and gfx1250.
To inspect a shipped library:

```bash
/opt/rocm/lib/llvm/bin/llvm-objdump --offloading /opt/rocm/lib/libvx_rpp.so
```

---

## Scope

vision-pack exists to **build, package, test, and deliver** the `amdrocm-vision`
package set on **Linux**. Windows and macOS are out of scope.

- build the four vision libraries plus the dependencies they require;
- package them so contents and dependency metadata match ROCm conventions;
- test that what is packaged actually loads and runs;
- make the artifacts easy for end users to obtain and try.

Fixing functional bugs inside the vision libraries is **out of scope**. Where a
library needs a change in order to build or package correctly, vision-pack
carries a workaround that names a filed upstream issue and is removed once that
issue is fixed — see [Known issues](#known-issues). Workarounds that would hide
a defect rather than record it are not acceptable.

---

## Build graph

```
Quartz nightly ROCm SDK (/opt/rocm)
  │  includes: HIP, RPP, rocDecode, rocJPEG, OpenMP, half, rocm_sysdeps
  │
  ├─────────────────────────────────────────────────┐
  │                                                 │
  ├── mivisionx          ──┐                        │  Third-party runtime deps
  ├── roccv              ──┤  parallel              │  (bundled, ships in
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
├── CHANGELOG.md                        release history
├── cmake/
│   ├── vision_pack_subproject.cmake    ExternalProject build orchestration
│   └── vision_pack_bundled_dep.cmake   helper macros for bundled deps
├── build_tools/
│   ├── fetch_rocm_sdk.py               download Quartz nightly SDK tarball
│   ├── rewrite_sonames.py              post-staging SONAME / RPATH isolation
│   ├── generate_manifest.py            build provenance written into staging
│   └── validate_packages.sh            per-DEB payload and metadata checks
├── packaging/
│   ├── CMakeLists.txt                  CPack config (DEB/RPM/TGZ)
│   ├── meta/                           amdrocm-vision{,-sdk,-tests} (equivs + rpm)
│   └── rpm/pythonpath.postin           RPM .pth into site-packages
├── .github/workflows/
│   ├── build.yml                       build → package.yml → test
│   ├── nightly.yml                     submodule bump → build → package
│   └── package.yml                     CPack → DEB/RPM/TGZ + GitHub release
│
├── mivisionx/      → ROCm/MIVisionX@develop
├── rocal/          → ROCm/rocAL@develop
├── roccv/          → ROCm/rocCV@develop
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

Install ROCm 10.2 or later. CI uses the nightly **dcgpu-tests** SDK tarball,
which carries the full SDK (HIP, compiler, `rocm_sysdeps`) *plus* the rpp,
rocDecode, and rocJPEG headers/cmake configs and the rocDecode build utils
(`share/rocdecode/utils`) all under a single prefix — no separate CV package
install is needed.

```bash
# Download + extract the dcgpu-tests SDK tarball to /opt/rocm-nightly
python3 build_tools/fetch_rocm_sdk.py \
    --gpu-family gfx94X-dcgpu-tests --dest /opt/rocm-nightly
```

Any GPU family works (the build is target-neutral); pick the variant that
bundles the CV packages, not one matching your gfx id. A pinned tarball URL
(`--url`) bypasses the nightly index — use it for run-id S3 artifacts that
have no rolling "latest".

For an existing `/opt/rocm` install you need the rpp, rocDecode, and rocJPEG
**dev** packages for headers and cmake configs, **plus `amdrocm-decode-test` and
`amdrocm-jpeg-test`**. The utility sources under `share/rocdecode/utils`
(`roc_video_dec.cpp`, `resize_kernels.cpp`) ship in the *test* packages, not the
dev ones — rocAL compiles them directly, so without them its configure step
fails with `Cannot find source file`. This is also why CI selects the
`dcgpu-tests` SDK variant: it carries them under a single prefix.

### System build tools (Ubuntu 22.04 / 24.04)

Only build-time tools are required from the OS package manager. All runtime
dependencies (libturbojpeg, libprotobuf, liblmdb, libsndfile) are built from
source in `third-party/` and bundled into `lib/rocm_sysdeps/lib/`.
ffmpeg, OpenCV, and libtar are excluded by design
([ADR 0005](docs/adr/0005-no-ffmpeg-opencv.md)).

```bash
sudo apt-get install -y cmake ninja-build python3-dev make patchelf
```

---

## Clone

```bash
git clone --recurse-submodules https://github.com/kiritigowda/vision-pack.git
cd vision-pack
```

Or if already cloned:

```bash
git submodule update --init --recursive
```

---

## Build

Run from the repository root. This compiles the libraries into per-project
stage dirs under `build/_subprojects/<lib>/stage`. It does **not** produce
packages; see [Packaging a local build](#packaging-a-local-build).

```bash
cmake -B build -S . \
    -DROCM_PATH=/opt/rocm \
    -DCMAKE_BUILD_TYPE=Release

cmake --build build --parallel $(nproc)
```

`cmake --install` on this project is not the product. It only installs bundled
runtime deps and the finder shims — it does not copy the vision stage trees or
run SONAME isolation. Use CPack (or the dist tarball CI already publishes).

### Component enable flags

All four libraries are ON by default. Disable individually:

```bash
cmake -B build -S . \
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
cmake -B build -S . \
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

Nightly CI publishes DEB, RPM, and
`vision-pack-dist-linux-multiarch-<ver>.tar.gz`. ROCm 10.2+ (HIP, RPP,
rocDecode, rocJPEG) must already be at `/opt/rocm`.

```bash
# DEB — one invocation satisfies vision-pack inter-Depends.
# Follow with `sudo apt-get install -f` if ROCm packages named in Depends
# are not already installed.
sudo dpkg -i amdrocm-*.deb

# RPM
sudo rpm -i amdrocm-*.rpm

# Dist tarball (no .pth — set PYTHONPATH)
sudo tar -xzf vision-pack-dist-linux-multiarch-*.tar.gz -C /opt/rocm
export PYTHONPATH=/opt/rocm/lib${PYTHONPATH:+:$PYTHONPATH}
```

Python modules live in `/opt/rocm/lib`. DEB/RPM ship `amdrocm-vision-pythonpath`
so system Python can `import` them without `PYTHONPATH`. A venv, conda env, or
the tarball still needs `PYTHONPATH` (or a copy of the `.pth`).

### Install layout

Files land directly under `/opt/rocm` — no new top-level directories.

```
/opt/rocm/
├── lib/
│   ├── libopenvx.so*, libvxu.so*, libvx_rpp.so*         MIVisionX
│   ├── librocal.so*, rocal_pybind*.so, amd/rocal/       rocAL + Python
│   ├── libroccv.so*, rocpycv*.so, rocpycv.pyi           rocCV + Python
│   ├── rocpydecode*.so, rocpyjpegdecode*.so             rocPyDecode
│   ├── pyRocVideoDecode/, pyRocJpegDecode/
│   ├── cmake/
│   │   ├── FindMIVisionX.cmake      shim (MIVisionX#1761)
│   │   ├── Findrocal.cmake          shim (rocAL#514)
│   │   └── roccv/                   rocCV Config.cmake
│   └── rocm_sysdeps/lib/            bundled runtime deps — same dir as
│       ├── libturbojpeg-rocm-vision.so*  ROCm's zlib, bzip2, liblzma ...
│       ├── libjpeg-rocm-vision.so*
│       ├── libprotobuf-rocm-vision.so*
│       ├── libprotobuf-lite-rocm-vision.so*
│       ├── liblmdb-rocm-vision.so*
│       └── libsndfile-rocm-vision.so*
├── include/
│   ├── mivisionx/                   OpenVX + AMD extension headers
│   ├── rocal/                       rocAL C++ API headers
│   └── roccv/                       rocCV C++ API headers
├── bin/
│   └── runvx                        MIVisionX graph execution tool
└── share/
    ├── mivisionx/                   samples (-devel), test (-test)
    ├── rocal/test/                  test sources + data
    ├── roccv/                       samples (-devel), test (-test)
    ├── rocpydecode/                 samples, tests
    └── rocpyjpegdecode/             samples, tests
```

The `.pth` is not under `/opt/rocm` and is not in the dist tarball. DEB writes
`/usr/lib/python3/dist-packages/amdrocm-vision.pth`. RPM `%post` writes the
same file into Python's `site-packages`.

All vision `.so` files have
`$ORIGIN:$ORIGIN/../lib/rocm_sysdeps/lib:$ORIGIN/llvm/lib` baked into their
RPATH, so bundled deps, ROCm's existing sysdeps, and `libomp.so` (rocAL links
`OpenMP::OpenMP_CXX`) resolve at runtime with no `LD_LIBRARY_PATH`.

**Every shipped RPATH is relative only.** Upstream link flags otherwise leave
build-host absolutes behind — `librocal.so` picked up `/opt/rocm/core-*/lib`,
`rocal_pybind.so` a bare `/llvm/lib`, and the bundled turbojpeg/libjpeg the CI
stage directory. Those resolve to nothing on a user's machine yet are searched
*ahead of* the relative entries. `rewrite_sonames.py` strips them, and CI fails
the build if any shipped `.so` carries an absolute or empty RPATH entry.

**Side-by-side SONAME isolation:** packaged bundled deps ship under private
`-rocm-vision` SONAMEs (`libturbojpeg-rocm-vision.so`, …) so a host copy of
turbojpeg/protobuf/lmdb/sndfile on the default loader path can never shadow the
vendored build. `librocal.so` / `rocal_pybind.so` are patched to reference
these names, and an isolated `libjpeg-rocm-vision.so` is added because rocAL
calls the raw libjpeg API (`jpeg_std_error`) that libturbojpeg does not export.
The rename is a post-staging pass (`build_tools/rewrite_sonames.py`) run before
CPack ([ADR 0004](docs/adr/0004-soname-isolation.md)).

**Dependencies come from the tree, not the host.** Bundled deps are built
without external codecs (`protobuf_WITH_ZLIB=OFF`, libsndfile
`ENABLE_EXTERNAL_LIBS=OFF` / `ENABLE_MPEG=OFF`), so nothing vision-pack ships
links a host copy of a library ROCm already vendors in `rocm_sysdeps`. CI fails
the build if any shipped `.so` has a `NEEDED` on a plain SONAME for which the
SDK provides a `librocm_sysdeps_*` equivalent.

**Python path registration:** `amdrocm-vision-pythonpath` installs
`amdrocm-vision.pth`, adding `/opt/rocm/lib` to system Python's `sys.path` so
`import rocal` / `import rocpycv` / `import rocpydecode` work without
`PYTHONPATH`. For venv/conda, copy the `.pth` into that environment's
site-packages, or export `PYTHONPATH=/opt/rocm/lib`.

---

## Packaging a local build

Stage each library, rewrite bundled SONAMEs, then CPack:

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

The aggregator does **not** compile or register tests — running `ctest` inside
`build/` finds nothing. Each library instead installs its test *sources* and
data as a `test` component under `share/<lib>/`. Those are standalone CMake
projects, built against the **installed** runtime. That is what the `-test`
packages deliver, and what CI mirrors by unpacking the **dist tarball** into
`ROCM_PATH` after packaging.

```bash
tar -xzf vision-pack-dist-linux-multiarch-*.tar.gz -C "$ROCM_PATH"
export PYTHONPATH="$ROCM_PATH/lib${PYTHONPATH:+:$PYTHONPATH}"

cmake -B test-build -S "$ROCM_PATH/share/mivisionx/test" \
    -DROCM_PATH="$ROCM_PATH" -DBACKEND=HIP
cmake --build test-build --parallel
ctest --test-dir test-build --output-on-failure

python3 -c "import rocal_pybind, amd.rocal, rocpycv, rocpydecode, rocpyjpegdecode"
```

GPU suites skip when `/dev/kfd` is absent. CPU configure/build/test failures
are real failures.

| Library | Test tree | Requires GPU |
|---|---|---|
| MIVisionX | `share/mivisionx/test` | GDF `*_CPU` cases do not; `*_GPU` do |
| rocAL | `share/rocal/test` | Yes — even `*_cpu` cases initialise a HIP context |
| rocCV | `share/roccv/test/cpp` | Yes |
| rocPyDecode | `share/rocpydecode/tests` | decode tests yes; `types_test.py` / import no |

---

## Third-party dependencies

| Dep | Version | License | Installed to | Notes |
|---|---|---|---|---|
| pybind11 | v3.1.0 | BSD-3 | — (build-time) | compiled into .so, not shipped |
| dlpack | v1.3 | Apache-2.0 | — (build-time) | header-only, not shipped |
| rapidjson | master | MIT | — (build-time) | compiled into librocal.so; v1.1.0 missing API needed by rocAL |
| protobuf | v3.21.12 | BSD-3 | `lib/rocm_sysdeps/lib/` | v3.22+ requires abseil nested submodule; `protobuf-lite` is also shipped |
| libjpeg-turbo | 3.2.0 | BSD/IJG | `lib/rocm_sysdeps/lib/` | rocAL links libturbojpeg.so dynamically; also ships the isolated libjpeg for rocAL's raw libjpeg API (`jpeg_std_error`) |
| lmdb | 1.0.1 | OpenLDAP | `lib/rocm_sysdeps/lib/` | rocAL Caffe/Caffe2 LMDB reader |
| libsndfile | 1.2.2 | LGPL-2.1 | `lib/rocm_sysdeps/lib/` | rocAL audio augmentation; built without external codecs |

**Excluded by design:** ffmpeg (libavcodec/avformat/avutil/swscale), OpenCV, and
libtar. rocAL has no build switch for these — it picks ffmpeg/libtar up via
`find_package(... QUIET)` — so the build passes
`-DCMAKE_DISABLE_FIND_PACKAGE_FFmpeg=ON` and
`-DCMAKE_DISABLE_FIND_PACKAGE_LibTar=ON`. OpenCV needs no flag; current rocAL
never looks for it.

---

## Package output

The `package.yml` CI workflow produces:

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
| `amdrocm-pydecode-test` | test sources (`share/rocpydecode/tests`, `share/rocpyjpegdecode/tests`) |
| `amdrocm-vision-sysdeps` | isolated libturbojpeg, libjpeg, libprotobuf, libprotobuf-lite, liblmdb, libsndfile (`-rocm-vision` SONAMEs) |
| `amdrocm-vision-pythonpath` | `.pth` registering `/opt/rocm/lib` |
| `amdrocm-vision` | meta — all runtimes, including pydecode |
| `amdrocm-vision-sdk` | meta — runtime + all `-devel` |
| `amdrocm-vision-tests` | meta — sdk + all `-test` |

---

## Known issues

Workarounds live in vision-pack, not in the submodules.

- **MIVisionX cmake exports missing** — no `MIVisionXConfig.cmake` installed;
  downstream consumers use the provided `FindMIVisionX.cmake` shim.
  [MIVisionX#1761](https://github.com/ROCm/MIVisionX/issues/1761)

- **rocAL cmake exports missing** — no `rocalConfig.cmake` installed.
  [rocAL#514](https://github.com/ROCm/rocAL/issues/514)

- **rocAL link/RPATH defects** — three separate upstream problems, all repaired
  on the staged tree by `rewrite_sonames.py`. Each repair should be deleted as
  the corresponding upstream fix lands:
  1. `librocal.so` calls the raw libjpeg API (`jpeg_std_error`) but
     `FindTurboJpeg.cmake` links only libturbojpeg, which does not export it —
     so the isolated libjpeg is added as an explicit `NEEDED`
     ([#39](https://github.com/kiritigowda/vision-pack/issues/39)).
  2. `rocal/CMakeLists.txt` forces `CMAKE_SKIP_INSTALL_RPATH`, discarding the
     install RPATH the build passes in; it is re-added afterwards
     ([#43](https://github.com/kiritigowda/vision-pack/issues/43)).
  3. `rocAL_pybind` puts `-Wl,-rpath='$ORIGIN:$ORIGIN/llvm/lib'` in
     `CMAKE_CXX_FLAGS`, where `$ORIGIN` is expanded away and leaves a bare,
     useless `/llvm/lib` entry.

- **libjpeg-turbo overrides `CMAKE_INSTALL_RPATH`** — its `CMakeLists.txt:334`
  does a plain `set(CMAKE_INSTALL_RPATH ${CMAKE_INSTALL_FULL_LIBDIR})`, which
  shadows the cache value vision-pack passes in, baking the build-time stage
  directory into the shipped libraries. The `-D` flag is passed anyway for the
  day upstream stops doing this, but the RPATH normalization in
  `rewrite_sonames.py` is what actually corrects it
  ([#45](https://github.com/kiritigowda/vision-pack/issues/45)).

- **MIVisionX `hip_cu_mask_tests` not installed** — the test suite registers
  `openvx_hip_cu_mask_remap_4K` but the `test` component did not ship the
  script. Fix is upstream:
  [MIVisionX#1766](https://github.com/ROCm/MIVisionX/pull/1766)
  ([#42](https://github.com/kiritigowda/vision-pack/issues/42)).

- **rocPyDecode `Development.Embed`** — upstream
  `find_package(Python3 Development)` needs `libpython.so`. manylinux's default
  CPython is statically linked, so CI forwards `Python3_ROOT_DIR` to
  `/opt/python-shared/cp312-cp312`. That is a workaround, not a reason to omit
  the package: a missing or empty `amdrocm-pydecode` fails CI.
  [rocPyDecode#290](https://github.com/ROCm/rocPyDecode/issues/290)

- **Python bindings in lib/ instead of site-packages** — rocAL, rocCV and
  rocPyDecode install `.so` extension modules to `/opt/rocm/lib`.
  `amdrocm-vision-pythonpath` drops `amdrocm-vision.pth` into system
  dist-packages (DEB) or site-packages (RPM `%post`). For a non-system
  interpreter, still `export PYTHONPATH=/opt/rocm/lib:$PYTHONPATH` or copy the
  `.pth`. Upstream site-packages fix:
  [rocAL#514](https://github.com/ROCm/rocAL/issues/514),
  [rocPyDecode#285](https://github.com/ROCm/rocPyDecode/issues/285)

- **rocPyDecode no COMPONENT grouping** — all `install()` directives lack
  runtime/dev/test separation, so CPack splits by path.
  [rocPyDecode#285](https://github.com/ROCm/rocPyDecode/issues/285)

- **rocAL WebDataset reader disabled** — requires libtar, excluded to keep
  the build self-contained (`-DCMAKE_DISABLE_FIND_PACKAGE_LibTar=ON`).

- **rocAL ffmpeg reader disabled** — requires libavcodec/avformat chain,
  excluded by design (`-DCMAKE_DISABLE_FIND_PACKAGE_FFmpeg=ON`).

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

---

## Tested configuration

CI builds in manylinux_2_28 (CPU). GPU suites skip without `/dev/kfd`.

| | |
|---|---|
| OS | Linux only — Ubuntu 24.04 LTS (local), manylinux_2_28 (CI) |
| ROCm | 10.2 (nightly `gfx94X-dcgpu-tests`) |
| GPU | gfx1100 when present (Radeon RX 7900 series) |
| CMake | 3.28 |
| Compiler | AMD clang (`amdclang++`) |
| Python | 3.12 |
| MIVisionX | 4.0.0 |
| rocAL | 2.5.0 |
| rocCV | 0.4.0 |
| rocPyDecode | 1.0.0 |

---

## License

[MIT License](LICENSE) — Copyright (c) 2026 Kiriti Gowda
