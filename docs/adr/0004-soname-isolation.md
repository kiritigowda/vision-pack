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

## Addendum: symbol binding (#66)

Renaming SONAMEs controls which file the loader *opens*. It does not control which definition a call *binds to*: the loader resolves each symbol by name (and version node) against every object already in the process, in load order. If a host copy is loaded first (an application linked against the system libjpeg, `LD_PRELOAD`, a `RTLD_GLOBAL` library), `librocal`'s calls bind to it even though the renamed bundled copy is also loaded. Where the ABIs differ, this produced silent data corruption (rocAL returned all-zero batches next to the system libjpeg).

- libjpeg, libturbojpeg and libsndfile are linked with a single private version node, `AMDROCM_VISION_1.0`, which no host library defines, so a versioned reference to it cannot be satisfied by a host copy. The node is injected through sanctioned workarounds only (`third-party/CMakeLists.txt`, [ADR 0003](0003-no-submodule-patches.md)): cache-seeded linker flags for libjpeg-turbo and a Python launcher for libsndfile's generated symbol file.
- A reference is only versioned if it is resolved at link time. rocAL links only libturbojpeg, so its libjpeg calls were unresolved and unversioned until libjpeg was added to the link line.
- `build_tools/rewrite_sonames.py` verifies the result: the bundled libs define only the private node and `librocal.so` has a versioned reference to each. patchelf cannot rewrite version definitions, so this pass cannot repair them.
- **Not covered: LMDB and protobuf.** Common distributions ship them without version information, and the loader lets an unversioned definition satisfy a versioned reference, so version nodes cannot isolate them. They would need to be linked statically into `librocal` with hidden symbols. libsndfile cannot be, since it is LGPL-2.1 and `librocal` is MIT.

## Consequences

### Positive
- Host copies of protobuf, turbojpeg, etc. are never loaded in place of the bundled versions.
- For libjpeg, libturbojpeg and libsndfile, a host copy already in the process cannot capture `librocal`'s calls either.
- Verified by clean-runner smoke test: install host conflicting libs, assert `ldd` still resolves bundled copies.

### Negative
- LMDB and protobuf calls can still bind to a host copy loaded first (see the addendum).
- Requires `patchelf` tool in CI environment.
- Renamed SONAMEs are non-standard and may confuse debugging.
- Must update CPack `FILES_MATCHING` patterns to match renamed files.

## References
- `build_tools/rewrite_sonames.py`
- `.github/workflows/package.yml` — smoke-test job
- Issue [#15](https://github.com/kiritigowda/vision-pack/pull/15)
