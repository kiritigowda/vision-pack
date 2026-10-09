#!/usr/bin/env bash
set -euo pipefail

# Package-install-path verification for vision-pack.
# Start from an empty Ubuntu 24.04 container, install ROCm core via apt from
# the AMD nightly repo, then install amdrocm-vision-sdk and amdrocm-vision-tests
# from a local apt repository built from the vision-pack .deb files.
#
# Environment variables:
#   ROCM_VERSION      ROCm version to install, e.g. 10.2 (default: 10.2)
#   ROCM_NIGHTLY_DATE   Nightly date YYYYMMDD (default: latest available)
#   VISION_PACK_REPO    Path to the local apt repo inside the container
#                       (default: /vision-pack-repo)
#   SKIP_TESTS          Set to 1 to skip running tests (install-only mode)

export DEBIAN_FRONTEND=noninteractive

ROCM_VERSION="${ROCM_VERSION:-10.2}"
ROCM_NIGHTLY_DATE="${ROCM_NIGHTLY_DATE:-}"
VISION_REPO="${VISION_PACK_REPO:-/vision-pack-repo}"

# Tooling needed to build and run the test suites.
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg build-essential cmake ninja-build \
  python3-dev python3-pip python3-venv ffmpeg patchelf libgl1 libglib2.0-0

# Resolve the nightly ROCm core apt repo URL.
ROCM_REPO_BASE="https://nightly.repo.amd.com/rocm/core/packages/ubuntu2404"
if [ -n "$ROCM_NIGHTLY_DATE" ]; then
  # The run ID is not known from the date alone; callers who pin a specific
  # build should set ROCM_REPO_URL directly.
  echo "ROCM_NIGHTLY_DATE set to ${ROCM_NIGHTLY_DATE}."
  echo "Please also set ROCM_REPO_URL to the full apt repo URL, e.g."
  echo "  ${ROCM_REPO_BASE}/<build-id>"
  exit 1
fi
ROCM_REPO_URL="${ROCM_REPO_URL:-${ROCM_REPO_BASE}}"

# Add the unsigned nightly repo. Production ROCm repos should use the signed
# keyring instead of trusted=yes.
echo "deb [arch=amd64 trusted=yes] ${ROCM_REPO_URL} stable main" \
  > /etc/apt/sources.list.d/amdrocm-nightly.list
apt-get update

# Install the ROCm core runtime plus HIP development CMake configs. The latter
# are required by rocCV's exported CMake config (HIPConfig.cmake / hip-config.cmake).
echo "=== Installing ROCm ${ROCM_VERSION} core SDK ==="
apt-get install -y --no-install-recommends \
  "amdrocm-base${ROCM_VERSION}" \
  "amdrocm-runtime-dev${ROCM_VERSION}"

# Add the local vision-pack apt repo.
echo "deb [arch=amd64 trusted=yes] file://${VISION_REPO} ./" \
  > /etc/apt/sources.list.d/vision-pack-nightly.list
cd "$VISION_REPO" && apt-get update

# Install the vision-pack SDK and its tests.
echo "=== Installing amdrocm-vision-sdk and tests ==="
apt-get install -y --no-install-recommends \
  "amdrocm-vision-sdk${ROCM_VERSION}" \
  "amdrocm-vision-tests${ROCM_VERSION}"

# Set up the build environment to use the apt-installed ROCm layout.
BASE_ROCM="/opt/rocm"
ROCM_PATH="/opt/rocm/core-${ROCM_VERSION}"
LLVM_PATH="$ROCM_PATH/lib/llvm"
export ROCM_PATH
export PATH="$ROCM_PATH/bin:$LLVM_PATH/bin:$BASE_ROCM/bin:$BASE_ROCM/llvm/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib/rocm_sysdeps/lib:$BASE_ROCM/lib:$BASE_ROCM/lib/rocm_sysdeps/lib:$LLVM_PATH/lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="$ROCM_PATH/lib:${PYTHONPATH:-}"
export CC="$LLVM_PATH/bin/amdclang"
export CXX="$LLVM_PATH/bin/amdclang++"

mkdir -p /logs
LOG="/logs/verify-apt-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

echo "=== rocminfo ==="
rocminfo || true

if [ "${SKIP_TESTS:-0}" = "1" ]; then
  echo "=== SKIP_TESTS=1; installation verified, skipping test suites ==="
  echo "=== Verification complete ==="
  echo "Log written to $LOG"
  exit 0
fi

echo "=== Python import smoke test ==="
python3 -c "
import rocal_pybind
import amd.rocal
import rocpycv
import rocpydecode
import rocpyjpegdecode
print('python-imports: ok')
"

echo "=== MIVisionX tests ==="
rm -rf /tmp/mivisionx-test && mkdir /tmp/mivisionx-test
cmake -G Ninja -S "$ROCM_PATH/share/mivisionx/test" -B /tmp/mivisionx-test \
  -DROCM_PATH="$ROCM_PATH" -DBACKEND=HIP
cmake --build /tmp/mivisionx-test --parallel "$(nproc)"
ctest --test-dir /tmp/mivisionx-test --output-on-failure

echo "=== rocAL tests ==="
rm -rf /tmp/rocal-test && mkdir /tmp/rocal-test
cmake -G Ninja -S "$ROCM_PATH/share/rocal/test" -B /tmp/rocal-test \
  -DROCM_PATH="$ROCM_PATH"
ctest --test-dir /tmp/rocal-test --output-on-failure

echo "=== rocCV tests ==="
rm -rf /tmp/roccv-test && mkdir /tmp/roccv-test
HIP_DEVICE_LIB_PATH="$LLVM_PATH/amdgcn/bitcode" \
cmake -G Ninja -S "$ROCM_PATH/share/roccv/test/cpp" -B /tmp/roccv-test \
  -DROCM_PATH="$ROCM_PATH" \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX"
cmake --build /tmp/roccv-test --parallel "$(nproc)"
ctest --test-dir /tmp/roccv-test --output-on-failure

echo "=== rocPyDecode type test ==="
python3 "$ROCM_PATH/share/rocpydecode/tests/types_test.py"

echo "=== Verification complete ==="
echo "Log written to $LOG"
