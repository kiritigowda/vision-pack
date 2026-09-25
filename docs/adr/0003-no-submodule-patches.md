# ADR 0003: No Submodule Patches Rule

## Status
Accepted — 2026-09

## Context
Upstream vision libraries (MIVisionX, rocAL, rocCV, rocPyDecode) evolve independently. Patching them in vision-pack would create a maintenance nightmare and fork from upstream.

## Decision
**Vision-library submodules are never patched.** All integration is done from vision-pack via sanctioned workarounds.

## Sanctioned Workarounds

1. **Cache variable seeding** — Set `<Name>_ROOT` before upstream `find_package()` calls via `vision_pack_provide_package()` / `vision_pack_provide_header_only()` macros.
2. **CMake arg forwarding** — Pass `-D` flags into ExternalProject via `vision_pack_subproject_declare(... CMAKE_ARGS ...)`.
3. **Finder shims** — Generate `Find<Name>.cmake` files into `CMAKE_MODULE_PATH` when upstream lacks CMake config exports.
4. **Post-build passes** — Modify staged build artifacts (e.g., SONAME rewriting) after upstream build completes.

## Consequences

### Positive
- Clean separation between vision-pack integration logic and upstream code.
- Easy submodule updates — `git submodule update --remote` with no merge conflicts.
- Forces upstream issues to be filed and tracked (e.g., MIVisionX#1761, rocAL#514).

### Negative
- Some workarounds are inelegant (e.g., pre-setting `Protobuf_LIBRARY_RELEASE` cache variables).
- Finder shims create technical debt until upstream adds proper CMake exports.
- Post-build passes (patchelf) are fragile and platform-dependent.

## References
- [README.md](../../README.md) — product is packages and the dist tarball
- `cmake/vision_pack_bundled_dep.cmake` — provide_* macros
- `cmake/shims/` — finder shims
