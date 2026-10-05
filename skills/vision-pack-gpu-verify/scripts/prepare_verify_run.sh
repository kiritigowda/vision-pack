#!/usr/bin/env bash
set -euo pipefail

VISION_PACK_DATE=""
ROCK_DATE=""
DEST_DIR="${PWD}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GPU_RENDER="/dev/dri/renderD128"
RUN_CONTAINER=false
DRY_RUN=false
FORCE_PRIVILEGED=false

usage() {
  cat <<'EOF'
Usage: prepare_verify_run.sh [OPTIONS]

Options:
  --vision-pack-date YYYYMMDD   Vision-pack nightly release date (default: latest)
  --rock-date YYYYMMDD          TheRock SDK nightly date to match (default: same as vision-pack-date)
  --dest DIR                    Download / output directory (default: PWD)
  --github-token TOKEN          GitHub token for API rate limits (optional)
  --gpu-render DEV              GPU render node to pass into container (default: /dev/dri/renderD128)
  --run-container               After downloading, build and run the verification container
  --force-privileged            Required when --run-container is used (safety opt-in)
  --dry-run                     Print what would be downloaded, do not fetch
  -h, --help                    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vision-pack-date) VISION_PACK_DATE="$2"; shift 2 ;;
    --rock-date) ROCK_DATE="$2"; shift 2 ;;
    --dest) DEST_DIR="$2"; shift 2 ;;
    --github-token) GITHUB_TOKEN="$2"; shift 2 ;;
    --gpu-render) GPU_RENDER="$2"; shift 2 ;;
    --run-container) RUN_CONTAINER=true; shift ;;
    --force-privileged) FORCE_PRIVILEGED=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

DEST_DIR="$(cd "$DEST_DIR" && pwd)"
mkdir -p "$DEST_DIR"

REPO="kiritigowda/vision-pack"
ROCK_INDEX="https://nightly.repo.amd.com/rocm/core/tarball"

api_curl() {
  local url="$1"
  if [[ -n "$GITHUB_TOKEN" ]]; then
    curl -fsSL -H "Authorization: token $GITHUB_TOKEN" "$url"
  else
    curl -fsSL "$url"
  fi
}

if [[ -z "$VISION_PACK_DATE" ]]; then
  echo "Resolving latest vision-pack nightly..."
  VP_TAG=$(api_curl "https://api.github.com/repos/$REPO/releases" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['tag_name'])")
else
  VP_TAG="nightly-$VISION_PACK_DATE"
fi

VP_RELEASE_URL="https://api.github.com/repos/$REPO/releases/tags/$VP_TAG"
echo "Vision-pack release: $VP_TAG"

RELEASE_JSON=$(api_curl "$VP_RELEASE_URL")
VP_NAME=$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
VP_DATE=$(echo "$VP_NAME" | grep -oP '\d{8}' || true)
if [[ -z "$ROCK_DATE" ]]; then
  ROCK_DATE="${VP_DATE:-$(date +%Y%m%d)}"
fi
echo "Matching TheRock SDK date: $ROCK_DATE"

echo "Resolving TheRock SDK tarball..."
ROCK_TARBALL=$(python3 - <<PY
import urllib.request, re
url = "$ROCK_INDEX/"
with urllib.request.urlopen(url) as r:
    html = r.read().decode()
pat = r"therock-dist-linux-gfx94X-dcgpu-tests-[^\"]*${ROCK_DATE}[^\"]*\.tar\.gz"
matches = sorted(set(re.findall(pat, html)))
if not matches:
    raise SystemExit("No matching TheRock tarball found for ${ROCK_DATE}")
print(matches[-1])
PY
)
ROCK_URL="$ROCK_INDEX/$ROCK_TARBALL"

echo "Resolving vision-pack DEB assets..."
ASSET_JSON=$(echo "$RELEASE_JSON" | python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin).get('assets', [])))")

filter_deb() {
  local suffix="$1"
  echo "$ASSET_JSON" | python3 -c "
import sys, json, urllib.parse
suffix = '$suffix'
for a in json.load(sys.stdin):
    name = a['name']
    if name.endswith('.deb') and suffix in name and 'amdrocm-vision-' in name:
        print(urllib.parse.unquote(a['browser_download_url']))
        break
"
}

DEBS=(
  "$(filter_deb 'Linux-pythonpath')"
  "$(filter_deb 'Linux-rocm-sysdeps-vision')"
  "$(filter_deb 'Linux-mivisionx.deb')"
  "$(filter_deb 'Linux-mivisionx-dev')"
  "$(filter_deb 'Linux-mivisionx-test')"
  "$(filter_deb 'Linux-rocal.deb')"
  "$(filter_deb 'Linux-rocal-dev')"
  "$(filter_deb 'Linux-rocal-test')"
  "$(filter_deb 'Linux-roccv.deb')"
  "$(filter_deb 'Linux-roccv-dev')"
  "$(filter_deb 'Linux-roccv-test')"
  "$(filter_deb 'Linux-rocpydecode.deb')"
  "$(filter_deb 'Linux-rocpydecode-test')"
)

REAL_DEBS=()
for u in "${DEBS[@]}"; do
  [[ -n "$u" ]] && REAL_DEBS+=("$u")
done

echo "Will download:"
echo "  TheRock SDK: $ROCK_URL"
for u in "${REAL_DEBS[@]}"; do
  echo "  DEB: $(basename "$u")"
done

if [[ "$DRY_RUN" == true ]]; then
  exit 0
fi

SDK_FILE="$DEST_DIR/$(basename "$ROCK_URL")"
if [[ -f "$SDK_FILE" ]]; then
  echo "SDK tarball already present: $SDK_FILE"
else
  echo "Downloading SDK tarball..."
  curl -fL --progress-bar -o "$SDK_FILE" "$ROCK_URL"
fi

mkdir -p "$DEST_DIR/debs"
# Remove stale DEBs from previous runs so a new nightly date doesn't mix with old packages.
rm -f "$DEST_DIR/debs"/amdrocm-vision-*.deb

for u in "${REAL_DEBS[@]}"; do
  fname=$(basename "$u")
  dest="$DEST_DIR/debs/$fname"
  if [[ -f "$dest" ]]; then
    echo "DEB already present: $fname"
  else
    echo "Downloading $fname..."
    curl -fL --progress-bar -o "$dest" "$u"
  fi
done

cat > "$DEST_DIR/verify-meta.json" <<EOF
{
  "vision_pack_tag": "$VP_TAG",
  "vision_pack_release_name": "$VP_NAME",
  "vision_pack_release_url": "https://github.com/$REPO/releases/tag/$VP_TAG",
  "therock_tarball_url": "$ROCK_URL",
  "therock_tarball_file": "$SDK_FILE",
  "therock_date": "$ROCK_DATE",
  "deb_files": $(find "$DEST_DIR/debs" -name '*.deb' -printf '"%f",' | sed 's/,$//; s/^/[/' | sed 's/$/]/'),
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

if [[ "$RUN_CONTAINER" != true ]]; then
  echo "Downloads complete. Re-run with --run-container --force-privileged to launch verification."
  exit 0
fi

if [[ "$FORCE_PRIVILEGED" != true ]]; then
  echo "ERROR: --run-container requires --force-privileged (safety opt-in)." >&2
  exit 1
fi

CONTAINER_NAME="vision-pack-verify-${ROCK_DATE}"

RUN_TTY=""
if [[ -t 0 ]]; then
  RUN_TTY="-t"
fi

if command -v docker >/dev/null 2>&1; then
  RUNTIME=docker
elif command -v podman >/dev/null 2>&1; then
  RUNTIME=podman
else
  echo "Neither docker nor podman found." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$SCRIPT_DIR/verify_in_container.sh" != "$DEST_DIR/verify_in_container.sh" ]]; then
  cp "$SCRIPT_DIR/verify_in_container.sh" "$DEST_DIR/verify_in_container.sh"
fi

echo "Launching verification container with $RUNTIME..."
$RUNTIME run --rm -i $RUN_TTY \
  --name "$CONTAINER_NAME" \
  --privileged \
  --device "/dev/kfd:/dev/kfd" \
  --device "$GPU_RENDER:$GPU_RENDER" \
  -e "ROCM_PATH=/opt/rocm" \
  -e "DEBIAN_FRONTEND=noninteractive" \
  -v "$SDK_FILE:/sdk.tar.gz:ro" \
  -v "$DEST_DIR/debs:/debs:ro" \
  -v "$DEST_DIR/verify_in_container.sh:/verify_in_container.sh:ro" \
  ubuntu:24.04 \
  bash /verify_in_container.sh

echo "Verification run complete. See container logs and $DEST_DIR/verify-meta.json."
