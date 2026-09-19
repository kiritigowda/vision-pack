# Contributing to vision-pack

vision-pack is a TheRock-style aggregator that builds and packages four AMD ROCm
computer-vision libraries (MIVisionX, rocAL, rocCV, rocPyDecode) as an optional
extension pack on top of a pre-built ROCm SDK. It does **not** build ROCm itself.

Please read this before opening a pull request.

## The core rule: do not patch the submodules

Integration is done entirely from vision-pack, never by editing the vision-library
submodules (`mivisionx/`, `rocal/`, `rocCV/`, `rocpydecode/`). If something appears to
need a submodule change, that is a signal to **file an upstream issue** and work around it
from vision-pack via one of:

- Setting `<Name>_ROOT` cache variables (the `vision_pack_provide_*` macros in
  `cmake/vision_pack_bundled_dep.cmake`) so an upstream `find_package()` resolves to a
  bundled copy unchanged.
- Passing `-D` cmake args into the ExternalProject from `CMakeLists.txt` /
  `cmake/vision_pack_subproject.cmake`.
- Generating finder shims (e.g. `cmake/shims/FindMIVisionX.cmake`) into `CMAKE_MODULE_PATH`.
- A post-build pass over the staged tree (e.g. `build_tools/rewrite_sonames.py`).

Any PR that modifies files under a submodule directory will be sent back.

## Building locally

Requires a pre-built ROCm SDK (10.2+) at `ROCM_PATH` that carries HIP, the compiler,
`rocm_sysdeps`, and the rpp / rocDecode / rocJPEG headers and cmake configs. See the
[README](README.md#prerequisites) for how to fetch the nightly `dcgpu-tests` tarball.

```bash
cmake -B build -S . -DROCM_PATH=/opt/rocm -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel "$(nproc)"
sudo cmake --install build            # installs into /opt/rocm
```

Component flags: `-DVISION_PACK_ENABLE_{MIVISIONX,ROCAL,ROCCV,ROCPYDECODE}=OFF`.
Bundling flags: `-DVISION_PACK_BUNDLE_{PYBIND11,DLPACK,RAPIDJSON,PROTOBUF,TURBOJPEG,LMDB,LIBSNDFILE}=OFF`
to build against system deps. Disabling rocAL auto-disables its bundled runtime deps.

## Adding a bundled third-party dependency

1. Add the submodule under `third-party/` pinned to a released tag or commit.
2. Wire it into `third-party/CMakeLists.txt`. Header-only deps are compiled into the
   vision `.so`s and never shipped; compiled runtime deps stage to
   `lib/rocm_sysdeps/lib/` (the same directory ROCm uses for zlib, bzip2, etc.) — no new
   top-level directories.
3. If a consuming submodule calls `find_package()` for it, seed the resolution with a
   `vision_pack_provide_*` macro rather than patching the submodule.
4. If it ships a runtime `.so` that could collide with a host copy, add it to the SONAME
   isolation list in `build_tools/rewrite_sonames.py`.

## Adding a new vision library

Declare it as a subproject via `vision_pack_subproject_declare()` in `CMakeLists.txt`,
add its component install rules and CPack mapping in `packaging/CMakeLists.txt`, and (if it
ships no package config) a `cmake/shims/Find<Name>.cmake` shim installed into `lib/cmake`.

## CI and reading failures

Three workflows run in `.github/workflows/`:

- **build.yml** — builds and stages into `build/staging/` (mirrors `/opt/rocm`), runs
  ctest, uploads the staging tree as an artifact. Includes a "Verify install" step that
  fails fast on missing libs, missing RPATH, or unresolved SONAMEs.
- **package.yml** — consumes the staging tree, runs CPack to cut DEB/RPM/TGZ, builds the
  `amdrocm-vision{,-sdk,-tests}` meta-packages, and runs two clean-runner guards: a
  side-by-side isolation `smoke-test` and a downstream `find_package` `findpackage-test`.
- **nightly.yml** — submodule bump → build → package → prerelease.

When CI fails, open the failing job's log and look for the `ERROR:` lines emitted by the
verification steps — they name the exact assertion that failed.

## Pull requests

- Keep the change focused; do not bundle unrelated cleanups.
- Confirm it builds locally and does not touch any submodule directory.
- Make sure CI is green before requesting review.
