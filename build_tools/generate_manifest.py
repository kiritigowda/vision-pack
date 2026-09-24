#!/usr/bin/env python3
"""
Emit the build manifest shipped at share/vision-pack/vision-pack-manifest.json.

It records exactly what went into a build: the vision-pack commit, the ROCm SDK
it was built against, the resolved commit of every submodule, and the version of
every bundled dependency. That is what makes a nightly artifact reproducible and
auditable after the fact -- without it there is no way to tell which upstream
revisions a given package came from (#29).

    build_tools/generate_manifest.py --output <path> [--rocm-path ...] [...]
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Bundled deps whose upstream version is not derivable from a tag on the
# submodule; kept in step with third-party/CMakeLists.txt.
BUNDLED_ROLE = {
    "third-party/pybind11": "build-time only (compiled in)",
    "third-party/dlpack": "build-time only (header-only)",
    "third-party/rapidjson": "build-time only (compiled in)",
    "third-party/protobuf": "runtime (lib/rocm_sysdeps/lib)",
    "third-party/libjpeg-turbo": "runtime (lib/rocm_sysdeps/lib)",
    "third-party/lmdb": "runtime (lib/rocm_sysdeps/lib)",
    "third-party/libsndfile": "runtime (lib/rocm_sysdeps/lib)",
}


def _run(args, cwd=REPO_ROOT):
    try:
        out = subprocess.run(args, cwd=cwd, check=True,
                             capture_output=True, text=True)
        return out.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def submodule_urls():
    """Map submodule path -> upstream URL from .gitmodules."""
    urls, path = {}, None
    gitmodules = REPO_ROOT / ".gitmodules"
    if not gitmodules.is_file():
        return urls
    for line in gitmodules.read_text().splitlines():
        line = line.strip()
        if line.startswith("path ="):
            path = line.split("=", 1)[1].strip()
        elif line.startswith("url =") and path:
            urls[path] = line.split("=", 1)[1].strip()
            path = None
    return urls


def submodules():
    """Resolved commit + described version for every submodule."""
    urls = submodule_urls()
    entries = []
    # `git submodule status` prints: <sha> <path> (<describe>)
    for line in _run(["git", "submodule", "status"]).splitlines():
        m = re.match(r"^[ +-]?(?P<sha>[0-9a-f]{7,40})\s+(?P<path>\S+)(?:\s+\((?P<desc>.*)\))?", line.strip())
        if not m:
            continue
        path = m.group("path")
        entry = {
            "path": path,
            "commit": m.group("sha"),
            "url": urls.get(path, ""),
        }
        if m.group("desc"):
            entry["describes"] = m.group("desc")
        if path in BUNDLED_ROLE:
            entry["role"] = BUNDLED_ROLE[path]
        else:
            entry["role"] = "vision library"
        entries.append(entry)
    return entries


def gpu_targets(staging_dir):
    """gfx code objects bundled into each shipped library, if readable."""
    if not staging_dir:
        return {}
    libdir = Path(staging_dir) / "lib"
    if not libdir.is_dir():
        return {}
    coverage = {}
    for base in ("libopenvx", "libvx_rpp", "libroccv", "librocal"):
        so = libdir / f"{base}.so"
        if not so.exists():
            continue
        real = so.resolve()
        # Read the fat binary section rather than llvm-objdump --offloading,
        # which extracts each bundle as a file beside the library.
        blob = subprocess.run(
            ["objcopy", "-O", "binary", "--only-section=.hip_fatbin",
             str(real), "/dev/stdout"],
            capture_output=True)
        if blob.returncode != 0 or not blob.stdout:
            continue
        found = sorted(set(re.findall(rb"gfx[0-9a-f]+", blob.stdout)))
        if found:
            coverage[base] = [t.decode() for t in found]
    return coverage


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--version", default="")
    ap.add_argument("--rocm-path", default="")
    ap.add_argument("--rocm-sdk", default="", help="Resolved SDK tarball name or URL")
    ap.add_argument("--build-type", default="")
    ap.add_argument("--release-type", default="ci")
    ap.add_argument("--staging-dir", default="", help="Staged tree, for gfx coverage")
    args = ap.parse_args()

    manifest = {
        "version": args.version,
        "sha": _run(["git", "rev-parse", "HEAD"]),
        "build_type": args.build_type,
        "release_type": args.release_type,
        "rocm_path": args.rocm_path,
        "rocm_sdk": args.rocm_sdk,
        "submodules": submodules(),
    }
    coverage = gpu_targets(args.staging_dir)
    if coverage:
        manifest["gpu_targets"] = coverage

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"[manifest] wrote {args.output}")
    print(f"[manifest] {len(manifest['submodules'])} submodule(s), "
          f"{len(coverage)} library gfx map(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
