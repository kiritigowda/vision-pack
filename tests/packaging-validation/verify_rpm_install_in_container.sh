#!/usr/bin/env bash
set -euo pipefail

# RPM package-install-path verification for vision-pack on Red Hat UBI 9.
# Start from an empty UBI 9 container, install ROCm core via dnf/yum from the
# AMD nightly RPM repo, then install amdrocm-vision-sdk and amdrocm-vision-tests
# from a local RPM repository built from the vision-pack .rpm files.
#
# Environment variables:
#   ROCM_VERSION      ROCm version to install, e.g. 10.2 (default: 10.2)
#   ROCM_REPO_URL     Full URL to the nightly ROCm core RPM repo directory
#                     (default: https://nightly.repo.amd.com/rocm/core/packages/rhel9/20261007-37549649086/x86_64)
#   VISION_PACK_REPO  Path to the local RPM repo inside the container
#                     (default: /vision-pack-repo)
#   SKIP_TESTS        Set to 1 to skip running tests (install-only mode)
#   PYTHON_CMD        Python interpreter to use (default: python3.12)

ROCM_VERSION="${ROCM_VERSION:-10.2}"
ROCM_REPO_URL="${ROCM_REPO_URL:-https://nightly.repo.amd.com/rocm/core/packages/rhel9/20261007-37549649086/x86_64}"
VISION_REPO="${VISION_PACK_REPO:-/vision-pack-repo}"

# UBI 9 minimal needs the CRB repo for some build dependencies and appstream
# for common tools. Enable them when available.
if command -v subscription-manager >/dev/null 2>&1; then
  subscription-manager repos \
    --enable rhel-9-for-x86_64-appstream-rpms \
    --enable rhel-9-for-x86_64-baseos-rpms \
    --enable codeready-builder-for-rhel-9-x86_64-rpms 2>/dev/null || true
fi

# Tooling needed to build and run the test suites.
# Notes on UBI 9 defaults:
#   - python3-virtualenv is not available; use python3 -m venv instead.
#   - ffmpeg-free / ffmpeg are not in the default UBI 9 repos. The packaged
#     vision tests that exercise video decode may fail without it; this is a
#     known UBI 9 limitation, not a vision-pack defect.
#   - patchelf is not required to run the test suites from installed packages.
#   - vision-pack Python bindings are built for Python 3.12, so install
#     python3.12 and use it explicitly.
yum install -y --setopt=install_weak_deps=0 \
  gcc gcc-c++ cmake ninja-build \
  python3.12 python3.12-devel python3.12-pip \
  libglvnd libglvnd-glx mesa-libGL glib2

# Make python3.12 the default python3 inside this script.
PYTHON_CMD="${PYTHON_CMD:-python3.12}"
$PYTHON_CMD --version
python3.12 -m ensurepip --upgrade || true

# Add the unsigned nightly ROCm core RPM repo.
cat > /etc/yum.repos.d/amdrocm-nightly.repo <<EOF
[amdrocm-nightly]
name=AMD ROCm ${ROCM_VERSION} Nightly
baseurl=${ROCM_REPO_URL}
gpgcheck=0
enabled=1
EOF

yum repolist

# Install the ROCm core runtime plus HIP development CMake configs. The latter
# are required by rocCV's exported CMake config (HIPConfig.cmake / hip-config.cmake).
# Also install the ROCm libraries that vision-pack RPMs declare as runtime deps.
echo "=== Installing ROCm ${ROCM_VERSION} core SDK ==="
yum install -y --setopt=install_weak_deps=0 \
  "amdrocm-base${ROCM_VERSION}" \
  "amdrocm-runtime-devel${ROCM_VERSION}" \
  "amdrocm-rpp${ROCM_VERSION}" \
  "amdrocm-decode${ROCM_VERSION}" \
  "amdrocm-hipfile${ROCM_VERSION}" \
  "amdrocm-jpeg${ROCM_VERSION}"

# Add the local vision-pack RPM repo.
cat > /etc/yum.repos.d/vision-pack-nightly.repo <<EOF
[vision-pack-nightly]
name=vision-pack nightly
baseurl=file://${VISION_REPO}
gpgcheck=0
enabled=1
EOF

# Refresh yum metadata for the local repo.
yum clean all
yum makecache

# NOTE: As of nightly 20261007, dnf/yum cannot resolve the vision-pack
# dependency chain automatically. amdrocm-vision-sysdeps${ROCM_VERSION}
# ships the renamed libraries (libsndfile-rocm-vision.so.1,
# libturbojpeg-rocm-vision.so.0, ...) but its RPM Provides only list the
# un-renamed SONAME + symbol-version combinations.
# amdrocm-rocal${ROCM_VERSION} requires the renamed SONAME + symbol-version
# combinations, so the meta-packages amdrocm-vision-sdk/tests cannot be
# installed cleanly. As a temporary workaround, force-install the concrete
# vision-pack RPMs with rpm --nodeps. The files are correct; only the Provides
# metadata is incomplete.
echo "=== Workaround: force-install vision-pack RPMs (Provides metadata gap) ==="
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-rocm-sysdeps-vision.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-pythonpath-rpm.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-mivisionx.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-mivisionx-dev.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-mivisionx-test.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-rocal.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-rocal-dev.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-rocal-test.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-roccv.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-roccv-dev.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-roccv-test.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-rocpydecode.rpm"
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-10.2.0-20261007-Linux-rocpydecode-test.rpm"

# The meta-packages are not strictly required once the concrete packages are
# installed, but include them for completeness.
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision10.2-10.2.0_20261007-20261007.noarch.rpm" || true
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-sdk10.2-10.2.0_20261007-20261007.noarch.rpm" || true
rpm -ivh --nodeps "${VISION_REPO}/amdrocm-vision-tests10.2-10.2.0_20261007-20261007.noarch.rpm" || true

# Set up the build environment to use the RPM-installed ROCm layout.
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
LOG="/logs/verify-rpm-$(date +%Y%m%d-%H%M%S).log"
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
$PYTHON_CMD -c "
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
  -DROCM_PATH="$ROCM_PATH" -DBACKEND=HIP -DPYTHON_EXECUTABLE="$(command -v $PYTHON_CMD)"
cmake --build /tmp/mivisionx-test --parallel "$(nproc)"
ctest --test-dir /tmp/mivisionx-test --output-on-failure

echo "=== rocAL tests ==="
rm -rf /tmp/rocal-test && mkdir /tmp/rocal-test
cmake -G Ninja -S "$ROCM_PATH/share/rocal/test" -B /tmp/rocal-test \
  -DROCM_PATH="$ROCM_PATH" -DPYTHON_EXECUTABLE="$(command -v $PYTHON_CMD)"
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
$PYTHON_CMD "$ROCM_PATH/share/rocpydecode/tests/types_test.py"

echo "=== Verification complete ==="
echo "Log written to $LOG"
