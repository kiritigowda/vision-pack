# vision-pack packaging validation

This directory contains a reproducible, end-to-end validation of the **apt-install
path** for vision-pack on Ubuntu 24.04. It starts from an empty container,
installs ROCm core packages from the AMD nightly apt repository, then installs
`amdrocm-vision-sdk` and `amdrocm-vision-tests` from a local apt repository built
from the vision-pack `.deb` files. No tarball extraction or `dpkg --force-depends`
is used.

## What it verifies

- `amdrocm-base` and `amdrocm-runtime-dev` install cleanly from the nightly repo.
- `amdrocm-vision-sdk` and `amdrocm-vision-tests` install cleanly from the
  vision-pack apt repository and pull in all declared dependencies.
- All four vision runtimes can be imported and exercised:
  - MIVisionX — 60 OpenVX/RunVX tests
  - rocAL — 8 CPU tests
  - rocCV — 40 C++ operator tests
  - rocPyDecode — type/import smoke test

## Why `amdrocm-runtime-dev` is required

`roccvConfig.cmake` calls `find_dependency(HIP)` and needs `HIPConfig.cmake` /
`hip-config.cmake`. Those CMake files are shipped in `amdrocm-runtime-dev`, not
in `amdrocm-base` or `amdrocm-runtime`. Installing only the runtime packages
will cause the rocCV test build to fail with:

```text
Could not find a package configuration file provided by "HIP" with any of the
following names: HIPConfig.cmake, hip-config.cmake
```

## Prerequisites (host)

- Docker with GPU device support for AMD GPUs.
- Membership in the host `video` group (and `render` group if present) so the
  container can access `/dev/kfd` and `/dev/dri`.
- A local apt repository built from the vision-pack `.deb` files, e.g.:

  ```bash
  mkdir -p local-apt-repo
  cp /path/to/vision-pack*.deb local-apt-repo/
  cd local-apt-repo
  dpkg-scanpackages . > Packages
  ```

- `sudo` access if your user is not in the `docker` group.

## Usage

```bash
cd tests/packaging-validation

# Build the local apt repo if you have not already
mkdir -p local-apt-repo
cp /path/to/vision-pack/debs/*.deb local-apt-repo/
(cd local-apt-repo && dpkg-scanpackages . > Packages)

# Run the validation. The container is removed automatically on exit.
sudo ./run_apt_install_container_2404.sh
```

The script mounts the local apt repo, the in-container verification script, and a
`logs/` directory. The full transcript is written to `logs/verify-apt-*.log`.

## Pinning a specific ROCm nightly

By default the script uses the rolling nightly index. To pin a specific build,
set `ROCM_REPO_URL` to the full apt repo path shown in the GitHub release notes:

```bash
export ROCM_REPO_URL="https://nightly.repo.amd.com/rocm/core/packages/ubuntu2404/20261007-37549649086"
sudo ./run_apt_install_container_2404.sh
```

## Files

| File | Purpose |
|------|---------|
| `run_apt_install_container_2404.sh` | Host wrapper that starts the Docker container with GPU access. |
| `verify_apt_install_in_container.sh` | In-container script that installs packages and runs all test suites. |
| `local-apt-repo/` | Place the vision-pack `.deb` files here and run `dpkg-scanpackages`. |
| `logs/` | Written by each validation run. |

## Expected results

```text
python-imports: ok
MIVisionX: 60/60 tests passed
rocAL:     8/8 tests passed
rocCV:     40/40 tests passed
rocPyDecode: passed
```
