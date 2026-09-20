# Architecture Decision Records (ADRs)

This directory records key architectural decisions in vision-pack. Each ADR explains the context, decision, consequences, and alternatives considered.

| ADR | Title | Date | Status |
|---|---|---|---|
| [0001](0001-external-project-build-model.md) | ExternalProject Build Model | 2026-09 | Accepted |
| [0002](0002-bundled-runtime-deps.md) | Bundled Runtime Dependencies | 2026-09 | Accepted |
| [0003](0003-no-submodule-patches.md) | No Submodule Patches Rule | 2026-09 | Accepted |
| [0004](0004-soname-isolation.md) | SONAME Isolation via patchelf | 2026-09 | Accepted |
| [0005](0005-no-ffmpeg-opencv.md) | Exclusion of ffmpeg and OpenCV | 2026-09 | Accepted |

## How to add a new ADR

1. Copy the template from an existing ADR.
2. Use the next sequential number.
3. Title format: `ADR NNNN: Brief Title`.
4. Status: `Proposed`, `Accepted`, `Deprecated`, or `Superseded by ADR NNNN`.
5. Submit as a PR; link the ADR from GOVERNANCE.md if it affects project direction.
