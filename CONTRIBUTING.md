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

### Build options

Component flags (all ON by default):
- `-DVISION_PACK_ENABLE_{MIVISIONX,ROCAL,ROCCV,ROCPYDECODE}=OFF` to disable individual libraries

Bundling flags (all ON by default):
- `-DVISION_PACK_BUNDLE_{PYBIND11,DLPACK,RAPIDJSON,PROTOBUF,TURBOJPEG,LMDB,LIBSNDFILE}=OFF` to build against system deps

Disabling rocAL auto-disables its bundled runtime deps.

### Using ccache (optional)

For faster rebuilds, enable ccache:
```bash
cmake -B build -S . -DROCM_PATH=/opt/rocm \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache
```

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
5. Update `CHANGELOG.md` under the `[Unreleased]` section.

## Adding a new vision library

1. Declare it as a subproject via `vision_pack_subproject_declare()` in `CMakeLists.txt`.
2. Add its component install rules and CPack mapping in `packaging/CMakeLists.txt`.
3. If it ships no package config, add a `cmake/shims/Find<Name>.cmake` shim installed into `lib/cmake`.
4. Update `README.md` with the new component in the build graph and package table.
5. Update `CHANGELOG.md` under the `[Unreleased]` section.

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

## Release process

1. Update `CHANGELOG.md`: move `[Unreleased]` items to a new version section.
2. Update `CMakeLists.txt`: bump the project version.
3. Create a git tag: `git tag -a vX.Y.Z -m "Release X.Y.Z"`
4. Push the tag: `git push origin vX.Y.Z`
5. GitHub Actions will create a release automatically from the tag.

## Pull requests

- Keep the change focused; do not bundle unrelated cleanups.
- Confirm it builds locally and does not touch any submodule directory.
- Update `CHANGELOG.md` under `[Unreleased]` with a brief description of your change.
- Update `README.md` if behavior or layout changed.
- Make sure CI is green before requesting review.
- Link any related issues in the PR description (e.g., `Closes #NN`).
