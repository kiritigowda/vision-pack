#!/usr/bin/env bash
set -euo pipefail

# Run the vision-pack packaging validation inside a clean Ubuntu 24.04 Docker
# container. The container is started with GPU device access and the local
# vision-pack apt repo mounted read-only.
#
# Usage:
#   sudo ./run_apt_install_container_2404.sh [DEB_REPO_DIR] [SCRIPT_DIR]
#
# Arguments:
#   DEB_REPO_DIR   Directory containing a dpkg-scanpackages-generated apt repo
#                  for the vision-pack .deb files.
#                  Default: ./local-apt-repo
#   SCRIPT_DIR     Directory containing verify_apt_install_in_container.sh.
#                  Default: .
#
# Environment:
#   ROCM_VERSION      ROCm version to install (default: 10.2)
#   ROCM_REPO_URL     Full URL to the nightly ROCm core apt repo.
#                     Default: https://nightly.repo.amd.com/rocm/core/packages/ubuntu2404

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB_REPO_DIR="${1:-${SCRIPT_DIR}/local-apt-repo}"
SCRIPT_SRC_DIR="${2:-${SCRIPT_DIR}}"

VIDEO_GID=$(getent group video | cut -d: -f3)
RENDER_GID=$(getent group render | cut -d: -f3 || echo "")

if [ -z "${VIDEO_GID:-}" ]; then
  echo "ERROR: could not determine the host 'video' group GID" >&2
  exit 1
fi

echo "Running apt-install-path Ubuntu 24.04 container validation"
echo "DEB repo:  $DEB_REPO_DIR"
echo "Script:    $SCRIPT_SRC_DIR/verify_apt_install_in_container.sh"
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
  -e "ROCM_REPO_URL=${ROCM_REPO_URL:-https://nightly.repo.amd.com/rocm/core/packages/ubuntu2404}" \
  -v "$DEB_REPO_DIR:/vision-pack-repo:ro" \
  -v "$SCRIPT_SRC_DIR/verify_apt_install_in_container.sh:/verify_apt_install_in_container.sh:ro" \
  -v "${SCRIPT_DIR}/logs:/logs" \
  ubuntu:24.04 /verify_apt_install_in_container.sh
