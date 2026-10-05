#!/usr/bin/env bash
set -euo pipefail

ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
export ROCM_PATH
export PATH="$ROCM_PATH/bin:$PATH"
export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib/rocm_sysdeps/lib:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="$ROCM_PATH/lib:${PYTHONPATH:-}"

mkdir -p /logs
LOG="/logs/verify-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  build-essential cmake ninja-build python3-dev python3-pip python3-venv \
  ffmpeg patchelf curl ca-certificates libgl1 libglib2.0-0

echo "Extracting TheRock SDK to $ROCM_PATH..."
mkdir -p "$ROCM_PATH"
tar -xzf /sdk.tar.gz -C "$ROCM_PATH" --strip-components=1

echo "Installing vision-pack DEBs..."
dpkg --force-depends -i /debs/*.deb

echo "=== rocminfo ==="
rocminfo

echo "=== hipinfo ==="
if command -v hipinfo >/dev/null 2>&1; then
  hipinfo
else
  echo "hipinfo not available in this SDK; skipping"
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
ctest --test-dir /tmp/mivisionx-test --output-on-failure || true

echo "=== rocAL tests ==="
rm -rf /tmp/rocal-test && mkdir /tmp/rocal-test
cmake -G Ninja -S "$ROCM_PATH/share/rocal/test" -B /tmp/rocal-test \
  -DROCM_PATH="$ROCM_PATH"
ctest --test-dir /tmp/rocal-test --output-on-failure || true

echo "=== rocCV tests ==="
rm -rf /tmp/roccv-test && mkdir /tmp/roccv-test
cmake -G Ninja -S "$ROCM_PATH/share/roccv/test/cpp" -B /tmp/roccv-test \
  -DROCM_PATH="$ROCM_PATH"
cmake --build /tmp/roccv-test --parallel "$(nproc)"
ctest --test-dir /tmp/roccv-test --output-on-failure || true

echo "=== rocPyDecode type test ==="
python3 "$ROCM_PATH/share/rocpydecode/tests/types_test.py" || true

echo "=== Verification complete ==="
echo "Log written to $LOG"
