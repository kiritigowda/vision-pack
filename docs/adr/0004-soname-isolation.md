# ADR 0004: SONAME Isolation via patchelf

## Status
Accepted — 2026-09

## Context
Bundled runtime deps (protobuf, libjpeg-turbo, lmdb, libsndfile) ship as shared libraries in `lib/rocm_sysdeps/lib/`. A host system may have different versions of these libraries on the default loader path, causing runtime symbol conflicts or ABI mismatches.

## Decision
Use `patchelf --replace-needed` post-build to rename bundled dependency SONAMEs to private `*-rocm-vision` variants, and update `librocal.so`'s DT_NEEDED entries to point to the renamed versions.

## Implementation
- `build_tools/rewrite_sonames.py` performs the renaming after staging but before packaging.
- Original SONAMEs (`libprotobuf.so.32`, `libturbojpeg.so.0`, etc.) become `libprotobuf-rocm-vision.so.32`, etc.
- Only `librocal.so` links against bundled deps; mivisionx, rocCV, and rocpydecode do not.

## Consequences

### Positive
- Host copies of protobuf, turbojpeg, etc. can no longer shadow bundled versions.
- Verified by clean-runner smoke test: install host conflicting libs, assert `ldd` still resolves bundled copies.

### Negative
- Requires `patchelf` tool in CI environment.
- Renamed SONAMEs are non-standard and may confuse debugging.
- Must update CPack `FILES_MATCHING` patterns to match renamed files.

## References
- `build_tools/rewrite_sonames.py`
- `.github/workflows/package.yml` — smoke-test job
- Issue [#15](https://github.com/kiritigowda/vision-pack/pull/15)
