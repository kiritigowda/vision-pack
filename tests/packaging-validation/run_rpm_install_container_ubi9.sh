#!/usr/bin/env bash
set -euo pipefail

# Run the vision-pack RPM packaging validation inside a clean Red Hat UBI 9
# Docker container. The container is started with GPU device access and the
# local vision-pack RPM repo mounted read-only.
#
# Usage:
#   sudo ./run_rpm_install_container_ubi9.sh [RPM_REPO_DIR] [SCRIPT_DIR]
#
# Arguments:
#   RPM_REPO_DIR   Directory containing a createrepo-generated RPM repo for the
#                  vision-pack .rpm files.
#                  Default: ./local-rpm-repo
#   SCRIPT_DIR     Directory containing verify_rpm_install_in_container.sh.
#                  Default: .
#
# Environment:
#   ROCM_VERSION      ROCm version to install (default: 10.2)
#   ROCM_REPO_URL     Full URL to the nightly ROCm core RPM repo.
#                     Default: https://nightly.repo.amd.com/rocm/core/packages/rhel9/20261007-37549649086/x86_64

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPM_REPO_DIR="${1:-${SCRIPT_DIR}/local-rpm-repo}"
SCRIPT_SRC_DIR="${2:-${SCRIPT_DIR}}"

VIDEO_GID=$(getent group video | cut -d: -f3)
RENDER_GID=$(getent group render | cut -d: -f3 || echo "")

if [ -z "${VIDEO_GID:-}" ]; then
  echo "ERROR: could not determine the host 'video' group GID" >&2
  exit 1
fi

echo "Running RPM-install-path UBI 9 container validation"
echo "RPM repo:  $RPM_REPO_DIR"
echo "Script:    $SCRIPT_SRC_DIR/verify_rpm_install_in_container.sh"
echo "video gid=$VIDEO_GID render gid=${RENDER_GID:-<none>}"

GROUP_ARGS=(--group-add "$VIDEO_GID")
if [ -n "$RENDER_GID" ]; then
  GROUP_ARGS+=(--group-add "$RENDER_GID")
fi

# Ensure the log directory exists so the container can write to it.
mkdir -p "${SCRIPT_DIR}/logs"

docker run --rm \
  --device=/dev/kfd \
  --device=/dev/dri \
  "${GROUP_ARGS[@]}" \
  -e "ROCM_VERSION=${ROCM_VERSION:-10.2}" \
  -e "ROCM_REPO_URL=${ROCM_REPO_URL:-https://nightly.repo.amd.com/rocm/core/packages/rhel9/20261007-37549649086/x86_64}" \
  -v "$RPM_REPO_DIR:/vision-pack-repo:ro" \
  -v "$SCRIPT_SRC_DIR/verify_rpm_install_in_container.sh:/verify_rpm_install_in_container.sh:ro" \
  -v "${SCRIPT_DIR}/logs:/logs" \
  redhat/ubi9 /verify_rpm_install_in_container.sh
