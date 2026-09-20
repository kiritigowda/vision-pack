# ADR 0005: Exclusion of ffmpeg and OpenCV

## Status
Accepted — 2026-09

## Context
rocAL upstream supports optional ffmpeg and OpenCV backends for video decoding and image I/O. These are large dependency trees.

## Decision
**Exclude ffmpeg and OpenCV by design** from the vision-pack build. rocAL is built with `-DBUILD_WITH_FFMPEG=OFF -DBUILD_WITH_OPENCV=OFF`.

## Rationale
- ffmpeg transitive deps: libavcodec → libvorbis → libFLAC → libopus → libmpg123 → ... (~50+ MB)
- OpenCV transitive deps: libgtk, libpng, libtiff, libwebp, ... (~100+ MB)
- Including either would violate the self-contained, minimal-dependency goal of vision-pack.

## Consequences

### Positive
- Smaller package size (~5 MB vs 150+ MB).
- Fewer CVE surface area in bundled dependencies.
- Simpler CI (no need to build ffmpeg from source in manylinux).

### Negative
- rocAL video reader pipeline is disabled.
- rocAL OpenCV augmentation ops are disabled.
- Users needing video decode must use rocPyDecode (hardware) or install ffmpeg separately.

## Future Consideration
If upstream rocAL makes ffmpeg/OpenCV optional at runtime (plugin-style), vision-pack could revisit this decision without rebuilding.

## References
- `CMakeLists.txt` — `-DBUILD_WITH_FFMPEG=OFF -DBUILD_WITH_OPENCV=OFF`
- `third-party/CMakeLists.txt` — no ffmpeg or opencv submodules
