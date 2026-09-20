# vision-pack Documentation

Welcome to the vision-pack documentation. This directory contains architecture decisions, design rationale, and developer guidance.

## Quick links

| Document | Purpose |
|---|---|
| [`../README.md`](../README.md) | User-facing build and install guide |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | How to contribute code, add deps, or add vision libraries |
| [`../GOVERNANCE.md`](../GOVERNANCE.md) | Maintainer model, labels, roadmap |
| [`../SECURITY.md`](../SECURITY.md) | Vulnerability reporting |
| [`../CHANGELOG.md`](../CHANGELOG.md) | Release history |
| [`adr/`](adr/) | Architecture Decision Records |
| [`../CLAUDE.md`](../CLAUDE.md) | Developer cheat sheet for build/packaging internals |

## For new contributors

1. Read [CONTRIBUTING.md](../CONTRIBUTING.md) for the build setup and the "no submodule patches" rule.
2. Read [GOVERNANCE.md](../GOVERNANCE.md) for the decision-making model.
3. Browse [adr/](adr/) to understand why the project uses ExternalProject, bundled deps, SONAME isolation, etc.
4. Check [CHANGELOG.md](../CHANGELOG.md) for what's changed recently.

## For maintainers

- Update `CHANGELOG.md` under `[Unreleased]` for every PR.
- Add ADRs for significant architectural changes.
- Keep [GOVERNANCE.md](../GOVERNANCE.md) roadmap up to date.
