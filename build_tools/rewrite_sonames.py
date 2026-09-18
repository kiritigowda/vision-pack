#!/usr/bin/env python3
"""
Rewrite the SONAMEs of vision-pack's bundled runtime deps for side-by-side
isolation from host copies (issue #4).

vision-pack ships protobuf, libjpeg-turbo, lmdb and libsndfile in
lib/rocm_sysdeps/lib/ under their stock SONAMEs (libprotobuf.so.32,
libturbojpeg.so.0, liblmdb.so.1, libsndfile.so.1, ...). On a host that already
has any of these on the default loader path, the dynamic loader can bind the
vision libs to the *host* copy instead of the bundled one — an ABI collision.
TheRock avoids this by renaming bundled sysdeps to a private SONAME; this script
does the same with patchelf as a post-build pass over the staged install tree.

Renaming scheme (major-version suffix preserved):
    libprotobuf.so.32  ->  libprotobuf-rocm-vision.so.32

Only librocal.so links these deps (mivisionx/rocCV/rocpydecode carry no
DT_NEEDED on them), so the consumer patch surface is just librocal.so*.

Usage:
    python3 build_tools/rewrite_sonames.py <staging-root>

<staging-root> is the install tree that mirrors /opt/rocm (e.g. build/staging),
containing lib/librocal.so and lib/rocm_sysdeps/lib/.

Idempotent: re-running on an already-rewritten tree is a no-op. Exits non-zero
if patchelf is missing or any consumer still lists a stock bundled SONAME.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# Bundled sysdep library stems we rewrite. Any lib<stem>.so* under
# rocm_sysdeps/lib is renamed to lib<stem>-rocm-vision.so*.
SYSDEP_STEMS = [
    "protobuf",
    "protobuf-lite",
    "turbojpeg",
    "jpeg",
    "lmdb",
    "sndfile",
]

SUFFIX = "-rocm-vision"

# Consumers (relative to staging root) that may carry a DT_NEEDED on the
# bundled sysdeps and must have those references rewritten.
CONSUMER_GLOBS = ["lib/librocal.so", "lib/librocal.so.*"]

# Matches libNAME.so, libNAME.so.MAJOR, libNAME.so.MAJOR.MINOR.PATCH
_SO_RE = re.compile(r"^lib(?P<stem>.+?)\.so(?P<ver>(?:\.\d+)*)$")


def _run(cmd):
    subprocess.run(cmd, check=True)


def patchelf_available():
    return shutil.which("patchelf") is not None


def new_basename(old_basename):
    """libprotobuf.so.32 -> libprotobuf-rocm-vision.so.32 (None if no match)."""
    m = _SO_RE.match(old_basename)
    if not m:
        return None
    stem = m.group("stem")
    if stem.endswith(SUFFIX):  # already rewritten
        return None
    if stem not in SYSDEP_STEMS:
        return None
    return f"lib{stem}{SUFFIX}.so{m.group('ver')}"


def rewrite_sysdeps(sysdeps_dir):
    """Rename bundled .so files + set their SONAME. Returns old->new SONAME map."""
    soname_map = {}
    # Real files first (skip symlinks — we recreate those from scratch after).
    real_sos = sorted(
        p for p in sysdeps_dir.glob("lib*.so*")
        if p.is_file() and not p.is_symlink()
    )
    for so in real_sos:
        new_name = new_basename(so.name)
        if new_name is None:
            continue
        new_path = so.with_name(new_name)
        so.rename(new_path)
        # The SONAME embedded in the ELF is the versioned major name, e.g.
        # libprotobuf.so.32 -> libprotobuf-rocm-vision.so.32. Query the current
        # one so we can map exactly what consumers reference.
        old_soname = subprocess.run(
            ["patchelf", "--print-soname", str(new_path)],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        new_soname = new_basename(old_soname) if old_soname else None
        if new_soname is None:
            # No SONAME recorded (rare) — derive from the major-version file name.
            new_soname = new_name
        _run(["patchelf", "--set-soname", new_soname, str(new_path)])
        if old_soname:
            soname_map[old_soname] = new_soname
        print(f"  renamed {so.name} -> {new_name}  (soname {old_soname or '-'} -> {new_soname})")

    # Remove any stale symlinks left under the old names, then recreate the
    # unversioned dev symlink (libNAME-rocm-vision.so -> ...so.MAJOR) pointing at
    # the highest-versioned real file for each renamed stem.
    for link in sorted(p for p in sysdeps_dir.glob("lib*.so*") if p.is_symlink()):
        if new_basename(link.name) is not None:
            link.unlink()  # stale stock-named symlink

    for stem in SYSDEP_STEMS:
        versioned = sorted(
            sysdeps_dir.glob(f"lib{stem}{SUFFIX}.so.*"),
            key=lambda p: [int(x) for x in p.name.split(".so.")[-1].split(".")],
        )
        if not versioned:
            continue
        target = versioned[-1]
        devlink = sysdeps_dir / f"lib{stem}{SUFFIX}.so"
        if devlink.exists() or devlink.is_symlink():
            devlink.unlink()
        devlink.symlink_to(target.name)
        print(f"  symlink {devlink.name} -> {target.name}")

    return soname_map


def patch_consumers(root, soname_map):
    if not soname_map:
        return
    consumers = []
    for pattern in CONSUMER_GLOBS:
        consumers.extend(sorted(root.glob(pattern)))
    for consumer in consumers:
        if consumer.is_symlink() or not consumer.is_file():
            continue
        needed = subprocess.run(
            ["patchelf", "--print-needed", str(consumer)],
            check=True, capture_output=True, text=True,
        ).stdout.split()
        for old_soname, new_soname in soname_map.items():
            if old_soname in needed:
                _run(["patchelf", "--replace-needed", old_soname, new_soname, str(consumer)])
                print(f"  {consumer.name}: NEEDED {old_soname} -> {new_soname}")


def verify(root):
    """Fail if any consumer still lists a stock bundled SONAME as NEEDED."""
    stock_sonames = set()
    for pattern in CONSUMER_GLOBS:
        for consumer in sorted(root.glob(pattern)):
            if consumer.is_symlink() or not consumer.is_file():
                continue
            needed = subprocess.run(
                ["patchelf", "--print-needed", str(consumer)],
                check=True, capture_output=True, text=True,
            ).stdout.split()
            for n in needed:
                new_name = new_basename(n)
                if new_name is not None:  # a stock bundled soname slipped through
                    stock_sonames.add(f"{consumer.name}:{n}")
    if stock_sonames:
        print("ERROR: consumers still reference stock bundled SONAMEs:")
        for s in sorted(stock_sonames):
            print(f"  {s}")
        return False
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("staging_root", type=Path,
                    help="Install tree mirroring /opt/rocm (e.g. build/staging)")
    args = ap.parse_args()

    root = args.staging_root
    sysdeps_dir = root / "lib" / "rocm_sysdeps" / "lib"
    if not sysdeps_dir.is_dir():
        print(f"ERROR: {sysdeps_dir} not found", file=sys.stderr)
        return 1
    if not patchelf_available():
        print("ERROR: patchelf not found on PATH", file=sys.stderr)
        return 1

    print(f"[rewrite_sonames] rewriting bundled sysdeps in {sysdeps_dir}")
    soname_map = rewrite_sysdeps(sysdeps_dir)
    if not soname_map:
        print("[rewrite_sonames] no stock-named bundled sysdeps found "
              "(already rewritten or none bundled)")
    print("[rewrite_sonames] patching consumers")
    patch_consumers(root, soname_map)

    if not verify(root):
        return 1
    print("[rewrite_sonames] done — bundled sysdeps isolated as *"
          f"{SUFFIX}.so*")
    return 0


if __name__ == "__main__":
    sys.exit(main())
