#!/usr/bin/env python3
"""
Download a nightly ROCm SDK tarball.

Whichever tarball is used must carry the full SDK (HIP, compiler, rocm_sysdeps)
*plus* rpp, rocDecode, rocJPEG headers/cmake configs and the rocDecode build
utils (share/rocdecode/utils) under a single prefix — so no separate deb
overlay is needed. The vision libs do contain GPU kernels, but the HIP compiler
emits a code object per gfx target and bundles them into one fat binary, so any
GPU family's tarball produces artifacts for every architecture; pick the variant
that bundles the CV packages above (dcgpu-tests / multi-arch), not by gfx id.

Two selection modes:

  1. Rolling family+date auto-select from the nightly index (default):
       python fetch_rocm_sdk.py --gpu-family gfx94X-dcgpu-tests --dest /opt/rocm-nightly
       python fetch_rocm_sdk.py --gpu-family gfx94X-dcgpu-tests --date 20260914
       python fetch_rocm_sdk.py --list-available --gpu-family gfx94X-dcgpu-tests

  2. Pin an exact tarball by full URL (e.g. a run-id multi-arch S3 artifact
     that has no rolling "latest" alias) — bypasses the index entirely:
       python fetch_rocm_sdk.py --url https://.../therock-dist-linux-....tar.gz \\
           --dest /opt/rocm-nightly
"""
import argparse
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

NIGHTLY_BASE = "https://nightly.repo.amd.com/rocm/core/tarball"
INDEX_URL = f"{NIGHTLY_BASE}/"


def list_available(gpu_family):
    """Return sorted list of available tarball names for a GPU family."""
    with urllib.request.urlopen(INDEX_URL) as resp:
        html = resp.read().decode()
    pattern = r"therock-dist-linux-" + re.escape(gpu_family) + r"-[^\"]*\.tar\.gz"
    return sorted(set(re.findall(pattern, html)))


def latest_tarball(gpu_family, date=None):
    # Returns (tarball_name, url) for the latest (or date-pinned) SDK.
    available = list_available(gpu_family)
    if not available:
        sys.exit(f"No tarballs found for GPU family '{gpu_family}'")

    if date:
        matches = [t for t in available if date in t]
        if not matches:
            sys.exit(f"No tarball found for family '{gpu_family}' on date '{date}'")
        name = matches[-1]
    else:
        name = available[-1]

    return name, f"{NIGHTLY_BASE}/{name}"


def download_and_extract(url, dest, strip=1):
    """Stream-download and extract tarball to dest."""
    dest.mkdir(parents=True, exist_ok=True)
    print(f"Downloading {url} -> {dest}", flush=True)
    cmd = [
        "bash", "-c",
        f"curl -fL --progress-bar '{url}' | tar -xzf - -C '{dest}' --strip-components={strip}"
    ]
    result = subprocess.run(cmd)
    if result.returncode != 0:
        sys.exit(f"Download/extract failed (exit {result.returncode})")
    print(f"Extracted to {dest}", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Fetch a nightly ROCm SDK tarball")
    parser.add_argument("--gpu-family", default="gfx94X-dcgpu-tests",
                        help="GPU family / variant name e.g. gfx94X-dcgpu-tests (default). "
                             "The dcgpu-tests variant bundles rpp/rocdecode/rocjpeg + "
                             "rocdecode/utils needed at build time.")
    parser.add_argument("--dest", type=Path, default=Path("/opt/rocm-nightly"),
                        help="Extraction destination directory (default: /opt/rocm-nightly)")
    parser.add_argument("--date", default=None,
                        help="Pin to a specific date YYYYMMDD (default: latest)")
    parser.add_argument("--url", default=None,
                        help="Full tarball URL to download, bypassing index scraping. "
                             "Use for run-id multi-arch artifacts with no rolling alias. "
                             "Overrides --gpu-family/--date.")
    parser.add_argument("--list-available", action="store_true",
                        help="List available tarballs and exit")
    parser.add_argument("--print-url", action="store_true",
                        help="Print tarball URL and exit without downloading")
    args = parser.parse_args()

    if args.list_available:
        tarballs = list_available(args.gpu_family)
        for t in tarballs:
            print(t)
        return

    if args.url:
        url = args.url
        print(f"Selected (pinned URL): {url.rsplit('/', 1)[-1]}")
    else:
        name, url = latest_tarball(args.gpu_family, args.date)
        print(f"Selected: {name}")

    if args.print_url:
        print(url)
        return

    download_and_extract(url, args.dest)


if __name__ == "__main__":
    main()
