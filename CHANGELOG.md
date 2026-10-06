# Changelog

All notable changes to vision-pack will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- rocAL finds the staged MIVisionX via `MIVisionX_PATH` instead of hard-coded
  library paths (#9).
- CI Python is keyed off a single `PYTHON_ABI` workflow env (still `cp312-cp312`)
  (#9).
- CI caches the compressed ROCm SDK archive by its exact resolved URL and uses
  that same URL in the build and every test leg (#9, #23).
### Fixed
- Bundled LMDB downgraded from 1.0.1 to 0.9.31 (Ubuntu's shipped version) —
  1.0.1's incompatible on-disk format (`MDB_DATA_VERSION` 3) broke rocAL's
  Caffe/Caffe2 LMDB readers on 0.9-format databases (`MDB_DATA_VERSION` 1);
  0.9.31 is the same version Ubuntu ships as `liblmdb0` (#58).
- Nightly packaging installs `gh` and `ca-certificates` in the Ubuntu
  container, grants `contents: write`, and publishes the prerelease with
  `GH_REPO` plus `--target` so `gh` does not need a local git checkout.
- Runtime packages no longer ship other components' empty directories, so
  installing only `amdrocm-roccv` does not make `import amd.rocal` succeed.
- Package version derivation matches only release tags (`v1.2.3` / `1.2.3`),
  so a `nightly-YYYYMMDD` prerelease tag no longer yields a non-numeric version
  (e.g. `nightly-20260926-3-gSHA`) that CPack rejects.
- `FindMIVisionX.cmake`'s `find_path()` NAMES ordering no longer short-circuits
  past `PATH_SUFFIXES`, so `MIVisionX_INCLUDE_DIRS` resolves to
  `include/mivisionx` instead of `include/`, and consumers of
  `MIVisionX::MIVisionX` can compile `#include <VX/vx.h>` (#63).
- `Findrocal.cmake` now exports both `include/rocal` and the parent
  `include/` on `rocal::rocal`, so both the unprefixed `#include
  "rocal_api.h"` form rocAL's own sources/tests use and the namespaced
  `#include <rocal/rocal_api.h>` form compile (#78).

### Added
- Bundled third-party dependencies now ship their license files, each in the
  package that carries its code, under `share/doc/<pkg>/licenses/<dep>/`:
  - `amdrocm-vision-sysdeps`: protobuf, libjpeg-turbo (`LICENSE.md` +
    `README.ijg`), lmdb (`LICENSE` + `COPYRIGHT`), libsndfile.
  - `amdrocm-rocal`: pybind11, dlpack, rapidjson (vision-pack's bundled copies).
  - `amdrocm-roccv`: pybind11, dlpack (rocCV's own vendored copies).
  - `amdrocm-pydecode`: its own `LICENSE`, plus pybind11 and dlpack.
  `validate_packages.sh` fails if a package ships a dep without its license,
  including the split IJG/LMDB texts.
- Each RPM's `License` tag now names exactly the licenses its payload carries
  (e.g. `amdrocm-vision-sysdeps` →
  `BSD-3-Clause AND IJG AND Zlib AND OLDAP-2.8 AND LGPL-2.1-or-later`, the
  vision libraries → `MIT`) instead of a bare `MIT` for everything. CPack has
  no per-component License override, so packaging builds all RPMs as `MIT` then
  re-emits the bundling packages in extra `cpack -G RPM` passes with their
  precise license; `build_tools/verify_rpm_licenses.sh` asserts every package's
  final tag.

## [0.2.0] — 2026-09-24

Packaging and CI cleanup. The product is DEB/RPM plus the dist tarball;
tests consume those artifacts. `amdrocm-pydecode` is required.

### Added
- GitHub issue templates and a pull request template.
- `CLAUDE.md` — developer guidance for build, packaging, and CI internals.
- RPM meta-packages (`amdrocm-vision`, `-sdk`, `-tests`) and an RPM `%post`
  that writes `amdrocm-vision.pth` into Python `site-packages`.
- Finder shims (`FindMIVisionX.cmake`, `Findrocal.cmake`) in the staging tree
  so the dist tarball can `find_package()` the same way `-devel` DEBs do.

### Changed
- `amdrocm-pydecode` is a required product package. Missing bindings, an empty
  DEB, or a failed import fail CI; `amdrocm-vision` always Depends on it.
- Library tests unpack `vision-pack-dist-linux-multiarch-*.tar.gz` after
  packaging. GPU suites skip when `/dev/kfd` is absent; CPU failures are red.
- `amdrocm-pydecode-test` keeps jpeg tests under `share/rocpyjpegdecode/tests`,
  matching the tarball.
- README updated for packages/tarball as the product (clone URL
  kiritigowda/vision-pack; no `cmake --install` install path).

### Fixed
- `amdrocm-mivisionx-devel` no longer ships `share/mivisionx/test` (collided
  with `-test`); `validate_packages.sh` rejects overlapping payload paths.
- `CMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF` on every vision library so host
  `ROCM_PATH` entries cannot leak into packages.
- Nightly `gh release create` no longer swallows publish errors.

---

## [0.1.0] — 2026-09-19

### Added
- **Build system** — TheRock-style ExternalProject orchestration for MIVisionX, rocAL, rocCV, and rocPyDecode.
- **Bundled runtime dependencies** — protobuf v3.21.12, libjpeg-turbo 3.2.0, lmdb 1.0.1, libsndfile 1.2.2 shipped in `lib/rocm_sysdeps/lib/`.
- **Bundled build-time dependencies** — pybind11 v3.1.0, dlpack v1.3, rapidjson (master).
- **CI/CD** — `build.yml`, `package.yml`, `nightly.yml` workflows with manylinux_2_28 container.
- **Packaging** — CPack-driven DEB/RPM/TGZ generation with component splits (`amdrocm-mivisionx`, `amdrocm-rocal`, etc.).
- **Meta-packages** — `amdrocm-vision`, `amdrocm-vision-sdk`, `amdrocm-vision-tests`.
- **SONAME isolation** — `build_tools/rewrite_sonames.py` renames bundled dep SONAMEs to avoid host-library collisions.
- **Python path registration** — `amdrocm-vision.pth` package so `import rocal` / `import rocpycv` work without `PYTHONPATH`.
- **Smoke tests** — clean-runner validation: install DEBs on pristine Ubuntu, assert `ldd` resolves bundled copies.
- **Find-module shims** — `FindMIVisionX.cmake` and `Findrocal.cmake` for downstream CMake discovery.
- **Nightly submodule bumps** — automated `develop` HEAD updates for all four vision libraries.
- **SDK fetcher** — `build_tools/fetch_rocm_sdk.py` downloads Quartz nightly tarballs with auto-select or pinned-URL modes.
- **Governance** — `CONTRIBUTING.md`, `GOVERNANCE.md`, `SECURITY.md`, `CODEOWNERS`.
- **License** — MIT License.

### Known Issues
- rocPyDecode is **not enabled in CI** (`ENABLE_ROCPYDECODE=OFF`) pending upstream [rocPyDecode#290](https://github.com/ROCm/rocPyDecode/issues/290).
- MIVisionX and rocAL lack upstream CMake config exports (MIVisionX#1761, rocAL#514) — shim find-modules provided.
- rocPyDecode install rules lack COMPONENT grouping (rocPyDecode#285) — path-based split used in packaging.

[Unreleased]: https://github.com/kiritigowda/vision-pack/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/kiritigowda/vision-pack/releases/tag/v0.2.0
[0.1.0]: https://github.com/kiritigowda/vision-pack/releases/tag/v0.1.0
