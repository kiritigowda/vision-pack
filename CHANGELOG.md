# Changelog

All notable changes to vision-pack will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Nightly packaging installs `gh` in the Ubuntu container, grants
  `contents: write`, and publishes the prerelease with `GH_REPO` plus
  `--target` so `gh` does not need a local git checkout inside the container.

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
