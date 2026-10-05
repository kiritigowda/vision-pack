---
name: "vision-pack-gpu-verify"
description: "Verify a vision-pack nightly release on local AMD GPU hardware using Docker + TheRock SDK."
---

# vision-pack GPU verification

Use when asked to verify a vision-pack nightly release on local GPU hardware,
or when a vision-pack build needs end-to-end GPU testing.

## What it does

1. Resolves a vision-pack nightly release and the matching TheRock ROCm SDK tarball.
2. Downloads the SDK tarball and the vision-pack DEB set into a local workspace.
3. Launches a privileged Ubuntu 24.04 container with `/dev/kfd` and `/dev/dri` passed through.
4. Installs the SDK at `/opt/rocm` and the vision-pack DEBs inside the container.
5. Builds and runs the library test suites for MIVisionX, rocAL, rocCV, and rocPyDecode.
6. Returns a summary of pass/fail results.

## Assumptions

- Linux host with AMD GPU, `amdgpu` driver loaded, `/dev/kfd` and `/dev/dri/renderD*` present.
- Docker or Podman installed and the current user can run privileged containers.
- Network access to `https://nightly.repo.amd.com/rocm/core/tarball` and GitHub releases.

## Workflow

### 1. Pick a release

If no date is given, the script resolves the latest vision-pack nightly.
Otherwise pin both vision-pack and SDK dates, e.g. `20261003`.

### 2. Download artifacts

Run from a clean workspace:

```bash
mkdir -p ~/vision-pack-verify && cd ~/vision-pack-verify
bash skills/vision-pack-gpu-verify/scripts/prepare_verify_run.sh --dry-run
bash skills/vision-pack-gpu-verify/scripts/prepare_verify_run.sh \
  --vision-pack-date 20261003 \
  --rock-date 20261003 \
  --dest . \
  --github-token "$GITHUB_TOKEN"
```

### 3. Run verification

```bash
bash skills/vision-pack-gpu-verify/scripts/prepare_verify_run.sh \
  --vision-pack-date 20261003 \
  --rock-date 20261003 \
  --dest . \
  --run-container \
  --force-privileged \
  --gpu-render /dev/dri/renderD128
```

### 4. Review results

The script writes `verify-meta.json` and streams a container log. CTest logs
are inside the container at `/tmp/{mivisionx,rocal,roccv}-test`.

## Safety rules

- Never install packages directly onto the host; keep all installs inside the container.
- The container needs `--privileged --device /dev/kfd:/dev/kfd --device /dev/dri`. Only use `--privileged` with explicit opt-in (`--force-privileged`).
- Pin both SDK and vision-pack versions for reproducibility.

## Known test quirks

- The SDK `amdclang` needs host GCC runtime libraries, so the container installs `build-essential`.
- The vision-pack DEBs declare ROCm package dependencies that are not resolvable from Ubuntu repositories. Install them with `dpkg --force-depends -i`; the TheRock SDK tarball supplies the actual runtime files.
- rocCV test executables are not pre-built; the script runs `cmake --build` before `ctest`.
- Container launch uses a conditional TTY so it works interactively and in CI/background contexts.
- Two upstream packaging/build issues may still fail regardless of the verification wrapper:
  - **MIVisionX** `openvx_remap_rgb_rgbx_constant_border` — missing test file in the installed package.
  - **rocAL** `video_tests_ffmpeg` / `video_tests_rocdecode` — prebuilt `librocal.so` lacks ffmpeg support.

## Files

- `scripts/prepare_verify_run.sh` — release resolution, downloads, container launch.
- `scripts/verify_in_container.sh` — container-side installs and test execution.
- `scripts/Dockerfile` — optional pre-built image.
- `references/README.md` — detailed usage and known issues.
