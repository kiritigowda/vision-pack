# ADR 0002: Bundled Runtime Dependencies

## Status
Accepted — 2026-09

## Context
rocAL depends on protobuf, libjpeg-turbo, lmdb, and libsndfile at runtime. These libraries may not be present on the target system, or may be at incompatible versions.

## Decision
Build these dependencies from source and bundle them into `lib/rocm_sysdeps/lib/`, following the same convention ROCm uses for its own sysdeps (zlib, bzip2, liblzma, libdrm).

## Consequences

### Positive
- Self-contained distribution — no external package manager dependencies at runtime.
- Version pinning — we control exact versions (protobuf v3.21.12, libjpeg-turbo 3.2.0, etc.).
- Consistent install layout with other ROCm components.

### Negative
- Larger package size (~5-10 MB per bundled .so).
- Security update lag — CVEs in bundled deps require vision-pack rebuild and re-release.
- SONAME collision risk with host system copies (mitigated by ADR 0004).

## Excluded Dependencies
ffmpeg and OpenCV are **excluded by design** — their transitive dependency chains (libavcodec → libvorbis → libFLAC → ...) would defeat the self-contained goal.

## References
- `third-party/CMakeLists.txt`
- `packaging/CMakeLists.txt`
- Issue [#33](https://github.com/kiritigowda/vision-pack/issues/33) (CVE scanning for bundled deps)
