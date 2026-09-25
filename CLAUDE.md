# CLAUDE.md — vision-pack

Guidance for working in this repo. Read this before touching the build, packaging, or CI.

## What this repo is

vision-pack is a **TheRock-style aggregator meta-repo** that builds and packages four AMD ROCm
computer-vision libraries as an optional extension pack on top of a **pre-built ROCm SDK**:

| Submodule | Upstream | Role |
|---|---|---|
| `mivisionx` | ROCm/MIVisionX@develop | OpenVX engine (`libopenvx`, `libvxu`) + RPP extension (`libvx_rpp`), `runvx` tool |
| `rocal` | ROCm/rocAL@develop | Augmentation library (`librocal`) + `rocal_pybind` Python binding |
| `rocCV` | ROCm/rocCV@develop | GPU image-processing (`libroccv`) + `rocpycv` Python binding |
| `rocpydecode` | ROCm/rocPyDecode@develop | Python bindings for rocDecode/rocJPEG hardware decode |

It does **not** build ROCm itself. It consumes a Quartz nightly SDK (HIP, RPP, rocDecode, rocJPEG,
OpenMP, `rocm_sysdeps`) and installs the vision libs **directly into `/opt/rocm`** with no new
top-level directories — identical conventions to every other ROCm component.

The end product is a set of DEB/RPM/TGZ packages (`amdrocm-mivisionx`, `amdrocm-rocal`,
`amdrocm-roccv`, `amdrocm-pydecode`, `amdrocm-vision-sysdeps`, plus `-devel`/`-test` variants and
`amdrocm-vision*` meta-packages). `amdrocm-pydecode` is required — a missing build
or empty package fails CI rather than being omitted from the meta Depends.

## How the packaging actually works (the whole flow)

0. **`build_tools/fetch_rocm_sdk.py`** downloads a single ROCm tarball to `ROCM_PATH`. That one
   tarball must carry the full SDK *plus* rpp / rocDecode / rocJPEG and `share/rocdecode/utils` —
   everything the vision libs need at build time, one prefix. Two selection modes:
   - **Rolling (default):** `--gpu-family <family> [--date YYYYMMDD]` scrapes the nightly index at
     `nightly.repo.amd.com/rocm/core/tarball/` and picks latest (or the dated build). Default family
     is `gfx94X-dcgpu-tests`. The vision libs *do* contain GPU kernels, but the HIP compiler
     emits a code object per gfx target and bundles them all into one fat binary, so *any*
     family builds for every architecture — pick the variant that bundles the CV packages,
     not by gfx id. Verify coverage with `llvm-objdump --offloading <lib>`.
   - **Pinned (`--url <full-tarball-url>`):** bypasses the index entirely. Use for run-id multi-arch
     S3 artifacts (e.g. `therock-nightly-artifacts.s3.amazonaws.com/<run-id>-linux/...`) that have no
     rolling "latest" alias. Overrides `--gpu-family`/`--date`.

   Both are wired as workflow inputs — `rocm_sdk_family`, `rocm_sdk_date`, `rocm_sdk_url` on
   `build.yml` and `nightly.yml` — so switching SDKs needs no code edit. The build.yml fetch step
   then verifies `rpp.h`, `rocjpeg.h`, and `roc_video_dec.cpp` exist in the tarball and fails fast if
   the chosen variant is missing any of them.
1. **`third-party/CMakeLists.txt`** builds the bundled deps. Header-only ones (pybind11, dlpack,
   rapidjson) are compiled into the vision `.so`s and never shipped. Compiled runtime deps
   (protobuf, libjpeg-turbo, lmdb, libsndfile) are staged to
   `build/third-party/rocm_sysdeps/` and installed to **`lib/rocm_sysdeps/lib/`** — the *same*
   directory ROCm already uses for zlib, bzip2, liblzma, etc. No new dirs.
2. **`cmake/vision_pack_subproject.cmake`** builds each vision lib as an **ExternalProject** with
   stamp-file ordering: mivisionx / rocCV / rocpydecode run in parallel (no inter-lib deps); rocAL
   runs last (needs mivisionx's staged `libopenvx`/`libvx_rpp` + all bundled runtime deps). Each
   lib installs to a per-project **stage dir** (`build/_subprojects/<name>/stage`) so dependents can
   find headers/libs before the final install.
3. **RPATH**: every vision `.so` gets `$ORIGIN:$ORIGIN/../lib/rocm_sysdeps/lib` baked in, so bundled
   deps + existing ROCm sysdeps resolve at runtime with no `LD_LIBRARY_PATH`.
4. **CI (`build.yml`)** stages everything into `build/staging/` (mirrors `/opt/rocm` layout) and
   uploads it as an artifact. The compressed ROCm SDK is cached by a SHA-256 of its exact resolved
   tarball URL, so build and test jobs reuse only byte-identical SDK inputs.
5. **CI (`package.yml`)** consumes that staging tree and runs **CPack** (config in
   `packaging/CMakeLists.txt`) to cut DEB/RPM/TGZ split by component, plus equivs meta-packages
   (`packaging/meta/amdrocm-vision.control.in`).

### Key files

| File | Purpose |
|---|---|
| `CMakeLists.txt` | Top-level orchestrator; declares subprojects + forwards per-lib cmake args |
| `cmake/vision_pack_subproject.cmake` | ExternalProject engine, prefix-path assembly, finder-shim generation |
| `cmake/vision_pack_bundled_dep.cmake` | `vision_pack_provide_package` / `_header_only` macros — set `<Name>_ROOT` so submodules' own `find_package()` calls resolve to bundled copies unmodified |
| `third-party/CMakeLists.txt` | Builds/installs the 7 bundled deps |
| `packaging/CMakeLists.txt` | CPack component→package mapping, DEB/RPM metadata |
| `build_tools/fetch_rocm_sdk.py` | Downloads the nightly `gfx94X-dcgpu-tests` SDK tarball |
| `.github/workflows/build.yml` | Build + stage + ctest inside manylinux_2_28 |
| `.github/workflows/nightly.yml` | Submodule bump → build → package → prerelease |
| `.github/workflows/package.yml` | CPack → DEB/RPM/TGZ + repo metadata + GH release |

## The core design principle (do not violate)

**Do not modify the vision-library submodules.** Integration is done entirely from vision-pack via:
- Setting `<Name>_ROOT` cache vars (the `vision_pack_provide_*` macros) so upstream `find_package()`
  calls resolve to bundled deps unchanged.
- Passing `-D` cmake args into each ExternalProject.
- Generating finder shims (e.g. `FindRapidJSON.cmake`) into `CMAKE_MODULE_PATH`.

If something needs a submodule patch, that is a signal to **file an upstream issue** and work around
it from vision-pack — not to edit the submodule.

## Hacks vs. necessary glue

The recent commit history is a run of `fix:` commits. Separate the two categories:

### Legitimate, keep as-is (necessary integration glue)

- `protobuf_MODULE_COMPATIBLE=ON` — protobuf 3.21 config-mode `find_package` doesn't set
  `Protobuf_FOUND`/`PROTOBUF_LIBRARIES`, which rocAL's `rocAL/CMakeLists.txt:166,216` requires. This
  is the documented way to get module-style vars from config mode. Correct.
- `-Wno-stringop-overread` on protobuf targets — genuine gcc-13 false positive in protobuf 3.21
  template copy ctors under manylinux_2_28.
- `CMAKE_POLICY_VERSION_MINIMUM=3.5` for libsndfile — its `cmake_minimum_required(3.1)` is rejected
  by CMake ≥3.30. Upstream problem, minimal workaround.
- `LIST_SEPARATOR "|"` in ExternalProject — standard technique for passing `;`-lists through.
- Forced `amdclang`/`amdclang++` via `CMAKE_CACHE_ARGS` — subprojects need ROCm's clang, not the
  top-level gcc.
- RapidJSON finder shim — rapidjson can't be `add_subdirectory`'d across an ExternalProject
  boundary; the shim is the clean alternative.
- libjpeg-turbo via `ExternalProject_Add` (not `add_subdirectory`) — upstream explicitly forbids
  add_subdirectory.

### The deb-mixing mess — RESOLVED (2026-09-15)

The old `build.yml` had a ~140-line "Install ROCm CV packages from nightly deb" step that stemmed
from **mixing two SDK sources**: the SDK *tarball* at `/opt/rocm-nightly` plus *deb packages* for
rpp/rocdecode/rocjpeg at `/opt/rocm/core-10.1`. That prefix split spawned a rocdecode/utils symlink,
`core-*` overlay globbing, a `ROCPYDECODE_ROCM_PATH` fallback, and a brittle per-deb content grep +
selective extraction to dodge the `roc_video_dec.cpp` regression (ROCm/rocm-systems#11609) and
80 MB of test video files.

**All of that is now deleted.** CI fetches a single **`gfx94X-dcgpu-tests`** ROCm 10.2 tarball from
`https://nightly.repo.amd.com/rocm/core/tarball/` that carries the full SDK *and* rpp / rocDecode /
rocJPEG headers, cmake configs, and `share/rocdecode/utils` (including `roc_video_dec.cpp`) all under
one `ROCM_PATH` prefix. Consequences:
- `build.yml` fetch step verifies the three critical paths exist in the tarball, then configures with
  a single `CMAKE_PREFIX_PATH=${ROCM_PATH};${ROCM_PATH}/lib/llvm`. No dpkg, no deb hunt, no symlink.
- `CMakeLists.txt` no longer has the `ROCPYDECODE_ROCM_PATH` detection block — rocpydecode gets
  `-DROCM_PATH=${ROCM_PATH}` directly.
- `vision_pack_subproject.cmake` no longer globs `core-*/lib/cmake`.

If a future SDK tarball stops shipping any of those three paths, the fetch step's verification loop
fails fast with a clear message — that's the signal to pick a different tarball variant, not to
reintroduce the deb overlay.

### Remaining upstream workaround (keep)

- **`Python3_ROOT_DIR` forwarding to shared Python.** rocCV and rocpydecode call
  `find_package(Python3 ... Development)` which needs `libpython3.x.so`. manylinux's default
  `/opt/python/cp312-cp312` is **statically linked** (no `libpython.so`), so CI points at
  `/opt/python-shared/${PYTHON_ABI}` (`PYTHON_ABI` is a workflow env, default `cp312-cp312`).
  - **Clean fix:** upstream should request only `Development.Module` (extension modules don't need
    `Development.Embed`/`libpython.so`). Tracked at rocPyDecode#290. The shared-Python forwarding is
    a reasonable interim workaround, threaded cleanly through the cmake args.

**Bottom line on cleanliness:** the CMake orchestration is clean and idiomatic, and CI's SDK
acquisition is now a single tarball fetch. The only remaining workaround is the shared-Python
forwarding, which is an upstream fix to file — never patch submodules.

## Build & test (local)

```bash
cmake -B build -S . -DROCM_PATH=/opt/rocm -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel $(nproc)
```

The product is packages and the dist tarball, not `cmake --install`. After
the build, copy each `_subprojects/<lib>/stage` into `build/staging`, install
the `runtime` component there, run `build_tools/rewrite_sonames.py`, then
CPack from `packaging/` — see [README.md](README.md).

Component flags: `-DVISION_PACK_ENABLE_{MIVISIONX,ROCAL,ROCCV,ROCPYDECODE}=OFF`.
Bundling flags: `-DVISION_PACK_BUNDLE_{PYBIND11,DLPACK,RAPIDJSON,PROTOBUF,TURBOJPEG,LMDB,LIBSNDFILE}=OFF`
to build against system deps (distro packaging). Disabling rocAL auto-disables its runtime deps.

## Test machine

`kiriti@santiago` — Ubuntu 24.04, ROCm at `/opt/rocm`, cmake 3.28, gcc 13, nasm 2.16.
No rsync — use `scp` or write files via ssh heredoc.

## Known upstream issues (work around, don't patch submodules)

- MIVisionX ships no `MIVisionXConfig.cmake` (MIVisionX#1761) — consumers use `FindMIVisionX.cmake`.
- rocAL ships no `rocalConfig.cmake` (rocAL#514).
- rocAL + rocPyDecode install Python `.so`s to `lib/` not site-packages (rocAL#514, rocPyDecode#285).
- rocPyDecode install() calls lack COMPONENT grouping (rocPyDecode#285).
- rocpydecode hardcoded utils path + `Development.Embed` requirement (rocPyDecode#290).
- rocAL WebDataset (libtar) and ffmpeg readers disabled by design to keep the tree self-contained.
