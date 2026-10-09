# Vision-pack packaging validation

Reusable scripts to validate vision-pack `.deb` and `.rpm` packages in clean
Docker containers using only the distribution package manager (no tarball/SDK
extract).

## Ubuntu 24.04 apt path

### What you need on the host

- A Docker engine (rootless or with `sudo`).
- The host user must be in the `video` and `render` groups, or those host GIDs
  must be passed into the container.
- A local apt repository built from the vision-pack `.deb` files. Example:

```bash
mkdir -p local-apt-repo/dists/stable/main/binary-amd64
cp *.deb local-apt-repo/
cd local-apt-repo
dpkg-scanpackages . /dev/null > dists/stable/main/binary-amd64/Packages
gzip -k -f dists/stable/main/binary-amd64/Packages
```

### Files

- `run_apt_install_container_2404.sh` — host wrapper that starts the container.
- `verify_apt_install_in_container.sh` — in-container validation script.

### Run

```bash
sudo ./run_apt_install_container_2404.sh [LOCAL_APT_REPO_DIR] [SCRIPT_DIR]
```

Environment variables:

- `ROCM_VERSION` — ROCm version to install, e.g. `10.2`.
- `ROCM_REPO_URL` — full URL to the unsigned nightly ROCm core apt repo.
  Default points to the `20261007-37549649086` Ubuntu 24.04 build.

### What the container does

1. Installs `amdrocm-base<ver>` and `amdrocm-runtime-dev<ver>` from the AMD
   nightly apt repo. The `-dev` package is **required** because it supplies
   `HIPConfig.cmake` / `hip-config.cmake` that rocCV's exported CMake config
   calls via `find_dependency(HIP)`.
2. Installs `amdrocm-vision-sdk<ver>` and `amdrocm-vision-tests<ver>` from the
   local `.deb` repo.
3. Runs Python import smoke tests, MIVisionX, rocAL, rocCV, and rocPyDecode
   test suites.

### Known good result (nightly 20261007)

| Suite         | Result          |
|---------------|-----------------|
| Python imports| ok              |
| MIVisionX     | 60/60 (100%)    |
| rocAL         | 8/8 (100%)      |
| rocCV         | 40/40 (100%)    |
| rocPyDecode   | passed          |

## Red Hat UBI 9 yum/dnf path

### What you need on the host

- A Docker engine (rootless or with `sudo`).
- The host user must be in the `video` and `render` groups.
- A local RPM repository built from the vision-pack `.rpm` files. Example:

```bash
mkdir -p local-rpm-repo
cp *.rpm local-rpm-repo/
cd local-rpm-repo
createrepo_c .
```

### Files

- `run_rpm_install_container_ubi9.sh` — host wrapper that starts the container.
- `verify_rpm_install_in_container.sh` — in-container validation script.

### Run

```bash
sudo ./run_rpm_install_container_ubi9.sh [LOCAL_RPM_REPO_DIR] [SCRIPT_DIR]
```

Environment variables:

- `ROCM_VERSION` — ROCm version to install, e.g. `10.2`.
- `ROCM_REPO_URL` — full URL to the unsigned nightly ROCm core RPM repo.
  Default points to the `20261007-37549649086` RHEL 9 build.
- `PYTHON_CMD` — Python interpreter to use. Default: `python3.12`.

### What the container does

1. Installs build tooling and **Python 3.12**. UBI 9 defaults to Python 3.9,
   but the vision-pack Python bindings are built for CPython 3.12.
2. Installs ROCm core packages from the AMD nightly yum repo:
   `amdrocm-base<ver>`, `amdrocm-runtime-devel<ver>`, `amdrocm-rpp<ver>`,
   `amdrocm-decode<ver>`, `amdrocm-hipfile<ver>`, and `amdrocm-jpeg<ver>`.
3. Adds the local vision-pack RPM repo.
4. **Workaround for 20261007:** the vision-pack RPMs cannot be installed
   cleanly with `yum` because `amdrocm-vision-sysdeps<ver>` provides the
   un-renamed SONAME + symbol-version combinations while `amdrocm-rocal<ver>`
   requires the renamed SONAME + symbol-version combinations. The concrete
   RPMs are therefore force-installed with `rpm -ivh --nodeps`. The library
   files are correct; only the RPM `Provides` metadata is incomplete. Once that
   metadata is fixed, this workaround can be removed and the standard
   `yum install amdrocm-vision-sdk<ver> amdrocm-vision-tests<ver>` path should
   work.
5. Runs the same test suites as the Ubuntu path.

### Known good result with workaround (nightly 20261007)

| Suite         | Result          |
|---------------|-----------------|
| Python imports| ok              |
| MIVisionX     | 60/60 (100%)    |
| rocAL         | 8/8 (100%)      |
| rocCV         | 40/40 (100%)    |
| rocPyDecode   | passed          |

### Open packaging issues found on RHEL 9

1. **RPM Provides metadata gap in `amdrocm-vision-sysdeps10.2`.** The package
   provides:
   - `libsndfile.so.1(libsndfile.so.1.0)(64bit)`
   - `libsndfile-rocm-vision.so.1()(64bit)`

   but `amdrocm-rocal10.2` requires:
   - `libsndfile-rocm-vision.so.1(libsndfile.so.1.0)(64bit)`

   The same pattern occurs for `libturbojpeg-rocm-vision.so.0(TURBOJPEG_*)`.
   This prevents `yum`/`dnf` from resolving the vision-pack SDK install.

2. **Python ABI mismatch on UBI 9.** The packaged `.so` Python bindings target
   CPython 3.12 (`...cpython-312...so`), while RHEL/UBI 9 ships Python 3.9 by
   default. Install `python3.12` from the UBI 9 appstream repo to run the
   import smoke test and Python-based test suites.

## Troubleshooting

- `docker: permission denied` — add the user to the `docker` group and
  re-login, or run the wrappers with `sudo`.
- `render` group not found inside the container — the scripts use numeric host
  GIDs (`--group-add $(getent group render | cut -d: -f3)`) because the base
  Ubuntu/UBI images do not define a `render` group.
- rocCV configure fails with `Could not find a package configuration file
  provided by HIP` — the ROCm runtime development package that contains
  `HIPConfig.cmake` / `hip-config.cmake` is not installed. On apt install
  `amdrocm-runtime-dev<ver>`; on yum install `amdrocm-runtime-devel<ver>`.
- rocPyDecode import fails with `librocdecode.so.1` missing on RHEL — install
  `amdrocm-decode<ver>` from the ROCm core repo.
