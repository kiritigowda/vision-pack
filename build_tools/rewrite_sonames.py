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

librocal.so and rocal_pybind.so link these deps directly (mivisionx/rocCV/
rocpydecode carry no DT_NEEDED on them), so the consumer patch surface is
librocal.so* plus rocal_pybind*.so. rocal_pybind links libturbojpeg via
${TurboJpeg_LIBRARIES} (rocAL_pybind/CMakeLists.txt), so it too references the
stock libturbojpeg.so.0 and must be rewritten, or its import dlopen fails with
"libturbojpeg.so.0: cannot open shared object file".

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
# bundled sysdeps and must have those references rewritten. rocal_pybind.so
# links ${TurboJpeg_LIBRARIES} directly (rocAL_pybind/CMakeLists.txt), so it
# references the stock libturbojpeg.so.0 just like librocal.so and must be
# rewritten too — otherwise `import rocal_pybind` fails to dlopen the renamed
# bundled turbojpeg.
CONSUMER_GLOBS = [
    "lib/librocal.so",
    "lib/librocal.so.*",
    "lib/rocal_pybind*.so",
]

# RPATH entries every consumer must carry so the loader finds the bundled
# sysdeps in rocm_sysdeps/lib at runtime. Matches VP_INSTALL_RPATH in
# CMakeLists.txt. rocAL forces CMAKE_SKIP_INSTALL_RPATH (rocAL CMakeLists.txt),
# stripping the RPATH our ExternalProject passes via -DCMAKE_INSTALL_RPATH, so
# librocal.so ships with no RPATH and cannot locate the renamed *-rocm-vision
# deps. We re-add it here (post-build, no submodule edit). rocal_pybind.so DOES
# ship an RPATH ($ORIGIN:$ORIGIN/llvm/lib for OpenMP/llvm), so we append the
# missing sysdeps entry rather than overwrite what it already has.
REQUIRED_RPATH_ENTRIES = ["$ORIGIN", "$ORIGIN/../lib/rocm_sysdeps/lib"]

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
    # SONAME -> real (renamed) file basename, so we can recreate the versioned
    # loader symlink (e.g. libprotobuf-rocm-vision.so.32 -> ...so.3.21.12.0).
    soname_real = {}
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
        soname_real[new_soname] = new_name
        print(f"  renamed {so.name} -> {new_name}  (soname {old_soname or '-'} -> {new_soname})")

    # Drop any stale symlinks left under the old stock names; we recreate the
    # ones we need from scratch below.
    for link in sorted(p for p in sysdeps_dir.glob("lib*.so*") if p.is_symlink()):
        if new_basename(link.name) is not None:
            link.unlink()

    # Recreate the versioned SONAME symlink (libNAME-rocm-vision.so.MAJOR ->
    # the real ...so.MAJOR.MINOR.PATCH file). This is the name every consumer's
    # DT_NEEDED points at, so the runtime loader resolves it here.
    for new_soname, real_name in soname_real.items():
        if new_soname == real_name:
            continue  # SONAME is already the real file itself
        link = sysdeps_dir / new_soname
        if link.exists() or link.is_symlink():
            link.unlink()
        link.symlink_to(real_name)
        print(f"  symlink {link.name} -> {real_name}")

    # Recreate the unversioned dev symlink (libNAME-rocm-vision.so ->
    # highest-versioned real file) for each renamed stem.
    for stem in SYSDEP_STEMS:
        versioned = sorted(
            (p for p in sysdeps_dir.glob(f"lib{stem}{SUFFIX}.so.*") if not p.is_symlink()),
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


def _current_rpath(path):
    """Return the DT_RUNPATH/DT_RPATH string on an ELF ('' if none)."""
    return subprocess.run(
        ["patchelf", "--print-rpath", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout.strip()


def _soname_of(path):
    """DT_SONAME of an ELF file, or its basename if it carries none."""
    out = subprocess.run(
        ["patchelf", "--print-soname", str(path)],
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    return out or path.name


def isolated_soname(sysdeps_dir, stem):
    """SONAME of the renamed bundled lib<stem>-rocm-vision.so* (None if absent)."""
    isolated_stem = f"{stem}{SUFFIX}"
    candidates = sorted(
        p for p in sysdeps_dir.glob(f"lib{isolated_stem}.so*")
        if p.is_file() and not p.is_symlink()
    )
    if not candidates:
        return None
    return _soname_of(candidates[0])


def patch_consumers(root, sysdeps_dir, soname_map):
    consumers = []
    for pattern in CONSUMER_GLOBS:
        consumers.extend(sorted(root.glob(pattern)))
    # rocAL's libjpeg decoder (rocAL/source/decoders/libjpeg/libjpeg_extra.cpp)
    # calls the raw libjpeg API (jpeg_std_error, jpeg_read_header, ...), but
    # rocAL's FindTurboJpeg.cmake links only libturbojpeg — which does NOT export
    # those symbols — so librocal.so ships with an unresolved jpeg_std_error and
    # fails to load (#39). Both libs come from the one bundled libjpeg-turbo
    # build and both are staged in rocm_sysdeps, so add the isolated libjpeg as
    # an explicit NEEDED. Post-build, no submodule edit.
    jpeg_soname = isolated_soname(sysdeps_dir, "jpeg")
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
        if jpeg_soname and jpeg_soname not in needed:
            _run(["patchelf", "--add-needed", jpeg_soname, str(consumer)])
            print(f"  {consumer.name}: +NEEDED {jpeg_soname} (raw libjpeg API)")
        # rocAL strips librocal.so's install RPATH (CMAKE_SKIP_INSTALL_RPATH),
        # so re-add the entries that locate the bundled sysdeps at runtime.
        # rocal_pybind.so keeps its own RPATH ($ORIGIN/llvm/lib for OpenMP), so
        # merge in only the missing entries rather than clobber it.
        rpath_parts = [p for p in _current_rpath(consumer).split(":") if p]
        missing = [e for e in REQUIRED_RPATH_ENTRIES if e not in rpath_parts]
        if missing:
            new_rpath = ":".join(rpath_parts + missing)
            _run(["patchelf", "--set-rpath", new_rpath, str(consumer)])
            print(f"  {consumer.name}: RPATH -> {new_rpath}")


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
    patch_consumers(root, sysdeps_dir, soname_map)

    if not verify(root):
        return 1
    print("[rewrite_sonames] done — bundled sysdeps isolated as *"
          f"{SUFFIX}.so*")
    return 0


if __name__ == "__main__":
    sys.exit(main())
