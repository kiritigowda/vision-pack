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

## Escalation

Disagreements that cannot be resolved in a pull request or issue thread are decided by the
lead maintainer. As the project grows and gains additional maintainers, this section will be
updated with a more formal process.
