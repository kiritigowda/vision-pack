# ADR 0001: ExternalProject Build Model

## Status
Accepted — 2026-09

## Context
vision-pack needs to build four separate AMD ROCm computer-vision libraries (MIVisionX, rocAL, rocCV, rocPyDecode) that each have their own CMake build systems, dependencies, and release cycles. They are maintained as independent upstream repositories.

## Decision
Use CMake's `ExternalProject` module to build each vision library as an independent subproject with stamp-file dependency ordering. This model is borrowed from [TheRock](https://github.com/ROCm/TheRock).

## Consequences

### Positive
- Each upstream library builds with its own CMake configuration unchanged — no submodule patches needed.
- Clean dependency ordering: mivisionx/rocCV/rocpydecode build in parallel; rocAL waits for mivisionx stage + bundled deps.
- Stage directories (`build/_subprojects/<name>/stage`) allow dependents to find headers/libs before final install.

### Negative
- More complex build orchestration than a monolithic `add_subdirectory()` approach.
- Cannot easily share CMake targets across subprojects — must use `CMAKE_PREFIX_PATH` and finder shims.
- Longer initial build times (each subproject re-runs CMake configure).

## Alternatives Considered
- **add_subdirectory()** — Rejected because upstream libraries expect to be top-level projects with their own `CMAKE_INSTALL_PREFIX` logic.
- **Super-build with separate repos** — Rejected because it complicates CI artifact sharing and versioning.

## References
- `cmake/vision_pack_subproject.cmake`
- TheRock's `therock_subproject.cmake`
