# vision-pack GPU verification

End-to-end GPU verification for vision-pack nightly releases.

This helper downloads a matching TheRock SDK tarball and the vision-pack DEB
set from a nightly GitHub release, launches a privileged container with GPU
access, installs the SDK and DEBs, and runs the packaged CTest suites for
MIVisionX, rocAL, rocCV, and the rocPyDecode smoke test.

## Files

| File | Purpose |
|------|---------|
| `scripts/prepare_verify_run.sh` | Resolves the nightly release, downloads artifacts, and launches the verification container. |
| `scripts/verify_in_container.sh` | Container entrypoint that installs the SDK/DEBs and runs all tests. |
| `scripts/Dockerfile` | Reference Ubuntu 24.04 image with the build/test dependencies pre-installed. |

## Requirements

- Docker or Podman
- AMD GPU with `/dev/kfd` and a render node (default `/dev/dri/renderD128`)
- User must be in the `video` and `render` groups, or use `sudo`
- Network access to GitHub releases and `nightly.repo.amd.com`
- A GitHub token is optional but helps avoid API rate limits

## Quick start

```bash
./skills/vision-pack-gpu-verify/scripts/prepare_verify_run.sh \
  --vision-pack-date 20261004 \
  --rock-date 20261004 \
  --dest ./verify-run \
  --run-container \
  --force-privileged
```

To see what would be downloaded without fetching anything:

```bash
./skills/vision-pack-gpu-verify/scripts/prepare_verify_run.sh \
  --vision-pack-date 20261004 \
  --rock-date 20261004 \
  --dest ./verify-run \
  --dry-run
```

## How it works

1. Resolve the vision-pack nightly release from `kiritigowda/vision-pack`.
2. Download the matching TheRock SDK tarball from `nightly.repo.amd.com`
   (the SDK date should match the vision-pack nightly date; mixing versions
   causes runtime failures such as `vxPublishKernels(vx_rpp) failed`).
3. Download the 13 vision-pack DEBs (runtime, dev, test packages plus
   `pythonpath`, `rocm-sysdeps-vision`, and `rocpydecode`).
4. Launch an Ubuntu 24.04 container with `--privileged` and GPU devices passed
   through.
5. Extract the SDK into `/opt/rocm`, then install the DEBs with
   `dpkg --force-depends -i` (the runtime files come from the SDK; the missing
   metadata-only ROCm dependencies are not available in Ubuntu repos). This
   leaves `apt` in a broken-dependency state inside the container, which is
   harmless for the single-purpose verification run but will block later
   `apt-get install` commands unless dependencies are satisfied another way.
6. Build and run each library's test suite via CMake/CTest.

## Notes / known issues

- **MIVisionX** usually passes 58/59 tests. Test #59
  (`openvx_remap_rgb_rgbx_constant_border`) fails because
  `remap_constant_border_tests/test_remap_constant_border.py` is missing from
  the installed test package. Filed upstream as
  [ROCm/MIVisionX#1813](https://github.com/ROCm/MIVisionX/issues/1813).

- **rocAL** usually passes 19/21 tests. The two video tests fail because the
  prebuilt `librocal.so` is compiled without ffmpeg support. Filed upstream as
  [ROCm/rocAL#560](https://github.com/ROCm/rocAL/issues/560).

- **rocCV** passes 40/40 tests.

- **rocPyDecode** smoke test passes.

Overall expected result is **~97.5%** of packaged tests passing; the remaining
failures are genuine upstream packaging/build defects that the verification
wrapper cannot fix.
