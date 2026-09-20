# Changelog

All notable changes to vision-pack will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- GitHub issue templates for bug reports and feature requests (`.github/ISSUE_TEMPLATE/`).
- Pull request template (`.github/pull_request_template.md`).
- `CLAUDE.md` — developer guidance for build, packaging, and CI internals.

### Changed
- README updated with comprehensive build graph, install layout, and tested configuration.

### Fixed
- N/A

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

[Unreleased]: https://github.com/kiritigowda/vision-pack/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kiritigowda/vision-pack/releases/tag/v0.1.0
