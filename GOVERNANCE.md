# Governance

vision-pack is a small maintainer-led project. This document describes who maintains it and
how decisions are made. It is intentionally lightweight and will grow as the project does.

## Maintainer

- [@kiritigowda](https://github.com/kiritigowda) — lead maintainer

The maintainer is responsible for reviewing and merging pull requests, cutting releases, and
setting technical direction. Code ownership is recorded in
[`.github/CODEOWNERS`](.github/CODEOWNERS).

## Decision making

- Routine changes (bug fixes, packaging fixes, CI improvements) are merged once they have
  maintainer review and green CI.
- Larger changes — new vision libraries, new bundled dependencies, changes to the packaging
  or SONAME-isolation model — should start as a GitHub issue so the approach can be
  discussed before implementation.
- The overarching design constraint is non-negotiable and applies to every change: **the
  vision-library submodules are never patched**; integration is done from vision-pack. See
  [CONTRIBUTING.md](CONTRIBUTING.md) for the rationale and the sanctioned workarounds.

## Labels and triage

vision-pack uses labels to categorize issues and PRs:

| Category | Labels |
|---|---|
| **Component** | `component:mivisionx`, `component:rocal`, `component:roccv`, `component:rocpydecode`, `component:packaging` |
| **Priority** | `priority:P0` (blocker), `priority:P1` (high), `priority:P2` (medium), `priority:P3` (low) |
| **Type** | `bug`, `enhancement`, `ci`, `docs`, `security` |
| **Status** | `upstream-blocked` (waiting on upstream ROCm fix) |

See [#26](https://github.com/kiritigowda/vision-pack/issues/26) for the full label proposal.

## Roadmap

### Short term (0.2.0)
- Enable rocPyDecode in CI ([#21](https://github.com/kiritigowda/vision-pack/issues/21))
- Add ccache for faster CI builds ([#23](https://github.com/kiritigowda/vision-pack/issues/23))
- Add Python import smoke tests ([#22](https://github.com/kiritigowda/vision-pack/issues/22))

### Medium term (0.3.0)
- Generate SBOM/dependency manifest ([#29](https://github.com/kiritigowda/vision-pack/issues/29))
- Add per-GPU-arch build matrix ([#34](https://github.com/kiritigowda/vision-pack/issues/34))
- Enable Dependabot for submodule security updates ([#24](https://github.com/kiritigowda/vision-pack/issues/24))

### Long term
- Publish container image ([#31](https://github.com/kiritigowda/vision-pack/issues/31))
- Add pip/conda packages ([#32](https://github.com/kiritigowda/vision-pack/issues/32))
- Add performance benchmarks ([#35](https://github.com/kiritigowda/vision-pack/issues/35))

## Escalation

Disagreements that cannot be resolved in a pull request or issue thread are decided by the
lead maintainer. As the project grows and gains additional maintainers, this section will be
updated with a more formal process.

## Release history

See [CHANGELOG.md](CHANGELOG.md) for the full release history.
