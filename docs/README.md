# vision-pack Documentation

Architecture decisions and developer guidance. The user-facing install and
build guide is [README.md](../README.md).

## Quick links

| Document | Purpose |
|---|---|
| [`../README.md`](../README.md) | Install, build, packages, layout |
| [`../CHANGELOG.md`](../CHANGELOG.md) | Release history |
| [`adr/`](adr/) | Architecture Decision Records |
| [`../CLAUDE.md`](../CLAUDE.md) | Build/packaging internals for agents |

## For new contributors

1. Read [README.md](../README.md) for the product (packages + dist tarball) and how to build it.
2. Read [ADR 0003](adr/0003-no-submodule-patches.md) — vision-library submodules are never patched.
3. Browse [adr/](adr/) for ExternalProject, bundled deps, and SONAME isolation.
4. Record user-facing changes under `[Unreleased]` in [CHANGELOG.md](../CHANGELOG.md).
