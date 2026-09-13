#!/usr/bin/env python3
"""
Download the latest Quartz nightly ROCm SDK tarball for a given GPU family.

Usage:
    python fetch_rocm_sdk.py --gpu-family gfx110X --dest /opt/rocm-nightly
    python fetch_rocm_sdk.py --gpu-family gfx110X --dest /opt/rocm-nightly --date 20260822
    python fetch_rocm_sdk.py --list-available --gpu-family gfx110X
"""
import argparse
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

NIGHTLY_BASE = "https://rocm.nightlies.amd.com/tarball-multi-arch"
INDEX_URL = f"{NIGHTLY_BASE}/"


def list_available(gpu_family):
    """Return sorted list of available tarball names for a GPU family."""
    with urllib.request.urlopen(INDEX_URL) as resp:
        html = resp.read().decode()
    pattern = r"therock-dist-linux-" + re.escape(gpu_family) + r"-[^\"]*\.tar\.gz"
    tarballs = sorted(set(re.findall(pattern, html)))
    return [t for t in tarballs if "test" not in t]


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
    parser = argparse.ArgumentParser(description="Fetch Quartz nightly ROCm SDK tarball")
    parser.add_argument("--gpu-family", default="gfx110X",
                        help="GPU family name e.g. gfx110X, gfx1151, gfx120X-all (default: gfx110X)")
    parser.add_argument("--dest", type=Path, default=Path("/opt/rocm-nightly"),
                        help="Extraction destination directory (default: /opt/rocm-nightly)")
    parser.add_argument("--date", default=None,
                        help="Pin to a specific date YYYYMMDD (default: latest)")
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

    name, url = latest_tarball(args.gpu_family, args.date)
    print(f"Selected: {name}")

    if args.print_url:
        print(url)
        return

    download_and_extract(url, args.dest)


if __name__ == "__main__":
    main()
