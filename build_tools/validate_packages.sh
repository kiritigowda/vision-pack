#!/usr/bin/env bash
#
# Validate every DEB vision-pack produces, one package at a time.
#
#   build_tools/validate_packages.sh <dir-with-debs>
#
# For each package it prints the control metadata (dpkg -I) and the payload
# listing (dpkg -c), then checks what the package is supposed to contain and
# how it is supposed to be laid out. Run it against a CPack output directory:
#
#   cpack -G DEB && build_tools/validate_packages.sh .
#
# Exits non-zero if any package fails a check.
set -u

DEB_DIR="${1:-.}"
FAILED=""
SUMMARY=""

# Payload each package must carry, as extended-regex patterns matched against
# the dpkg -c path list. Packages absent from this table are still checked for
# metadata and layout, just not for specific contents.
expected_contents() {
  case "$1" in
    amdrocm-mivisionx)          echo 'lib/libopenvx\.so lib/libvxu\.so lib/libvx_rpp\.so bin/runvx' ;;
    amdrocm-mivisionx-devel)    echo 'include/mivisionx/ lib/cmake/FindMIVisionX\.cmake' ;;
    amdrocm-mivisionx-test)     echo 'share/mivisionx/test/ share/mivisionx/test/hip_cu_mask_tests/' ;;
    amdrocm-rocal)              echo 'lib/librocal\.so lib/rocal_pybind.*\.so' ;;
    amdrocm-rocal-devel)        echo 'include/rocal/ lib/cmake/Findrocal\.cmake' ;;
    amdrocm-rocal-test)         echo 'share/rocal/test/' ;;
    amdrocm-roccv)              echo 'lib/libroccv\.so lib/rocpycv.*\.so' ;;
    amdrocm-roccv-devel)        echo 'include/roccv/ lib/cmake/roccv/' ;;
    amdrocm-roccv-test)         echo 'share/roccv/test/' ;;
    amdrocm-pydecode)           echo 'lib/rocpydecode.*\.so lib/rocpyjpegdecode.*\.so lib/pyRocVideoDecode/ lib/pyRocJpegDecode/' ;;
    amdrocm-pydecode-test)      echo 'share/rocpydecode/tests/ share/rocpyjpegdecode/tests/' ;;
    amdrocm-vision-sysdeps)     echo 'libturbojpeg-rocm-vision\.so libjpeg-rocm-vision\.so libprotobuf-rocm-vision\.so liblmdb-rocm-vision\.so libsndfile-rocm-vision\.so' ;;
    amdrocm-vision-pythonpath)  echo 'dist-packages/amdrocm-vision\.pth' ;;
    *)                          echo '' ;;
  esac
}

# The equivs meta-packages are a different shape from the CPack ones: they
# deliberately carry no payload, and equivs always emits the three standard
# Debian doc files under /usr/share/doc. Their value is entirely in what they
# pull in, so that is what gets checked.
is_meta() {
  case "$1" in
    amdrocm-vision|amdrocm-vision-sdk|amdrocm-vision-tests) return 0 ;;
    *) return 1 ;;
  esac
}

expected_meta_depends() {
  case "$1" in
    amdrocm-vision)
      echo 'amdrocm-mivisionx amdrocm-rocal amdrocm-roccv amdrocm-pydecode' ;;
    amdrocm-vision-sdk)
      echo 'amdrocm-vision amdrocm-mivisionx-devel amdrocm-rocal-devel amdrocm-roccv-devel' ;;
    amdrocm-vision-tests)
      echo 'amdrocm-vision-sdk amdrocm-mivisionx-test amdrocm-rocal-test amdrocm-roccv-test amdrocm-pydecode-test' ;;
    *) echo '' ;;
  esac
}

# Packages that legitimately declare no dependencies.
declares_no_deps_ok() {
  case "$1" in amdrocm-vision-sysdeps|amdrocm-vision-pythonpath) return 0 ;; *) return 1 ;; esac
}

check_package() {
  local deb="$1" fail=0
  local pkg ver arch maint desc deps contents paths files links

  pkg="$(dpkg-deb --field "$deb" Package 2>/dev/null || echo '')"
  [ -n "$pkg" ] || { echo "  ERROR: cannot read control data"; return 1; }
  ver="$(dpkg-deb --field "$deb" Version)"
  arch="$(dpkg-deb --field "$deb" Architecture)"
  maint="$(dpkg-deb --field "$deb" Maintainer)"
  desc="$(dpkg-deb --field "$deb" Description)"
  deps="$(dpkg-deb --field "$deb" Depends)"

  echo "------------------------------------------------------------------"
  echo "### ${pkg}  (${deb##*/})"
  echo "--- control metadata (dpkg -I) ---"
  dpkg-deb --info "$deb" | sed -n '/^ Package:/,$p' | sed 's/^/  /'

  contents="$(dpkg-deb --contents "$deb")"
  # Field 6 is the path; $NF would be the link target on symlink lines.
  paths="$(echo "$contents" | awk '$1 !~ /^d/ {print $6}')"
  files="$(echo "$contents" | awk '$1 !~ /^d/' | grep -c . || true)"
  links="$(echo "$contents" | awk '$1 ~ /^l/' | grep -c . || true)"

  echo "--- payload (dpkg -c) ---"
  echo "$contents" | awk '$1 !~ /^d/' | sed 's/^/  /'
  echo "--- ${files} file(s), ${links} symlink(s) ---"

  # --- metadata completeness -------------------------------------------------
  for field in "Version:${ver}" "Architecture:${arch}" "Maintainer:${maint}" \
               "Description:${desc}"; do
    if [ -z "${field#*:}" ]; then
      echo "  ERROR: control field ${field%%:*} is empty"; fail=1
    fi
  done
  case "$ver" in
    [0-9]*) ;;
    *) echo "  ERROR: version '${ver}' does not start with a digit"; fail=1 ;;
  esac
  if [ -z "$deps" ] && ! declares_no_deps_ok "$pkg"; then
    echo "  ERROR: ${pkg} declares no dependencies"; fail=1
  fi

  # --- meta-packages ---------------------------------------------------------
  # No payload of their own; what matters is that they pull in the right set.
  if is_meta "$pkg"; then
    local unexpected want_dep
    unexpected="$(echo "$paths" | grep -v '^\./usr/share/doc/' || true)"
    if [ -n "$unexpected" ]; then
      echo "  ERROR: meta-package ships files beyond /usr/share/doc:"
      echo "$unexpected" | sed 's/^/      /'; fail=1
    else
      echo "  carries no payload beyond /usr/share/doc: OK"
    fi
    for want_dep in $(expected_meta_depends "$pkg"); do
      # Match on a word boundary so amdrocm-vision does not satisfy a check
      # for amdrocm-vision-sdk.
      if echo "$deps" | grep -qE "(^|[, ])${want_dep}( |,|\(|$)"; then
        echo "  pulls in ${want_dep}: OK"
      else
        echo "  ERROR: ${pkg} does not depend on ${want_dep}"; fail=1
      fi
    done
    if [ "$fail" -eq 0 ]; then
      echo "  => ${pkg}: PASS"
      SUMMARY="${SUMMARY}  PASS  ${pkg} (meta, $(echo "$deps" | tr ',' '\n' | grep -c .) deps)\n"
    else
      echo "  => ${pkg}: FAIL"
      SUMMARY="${SUMMARY}  FAIL  ${pkg} (meta)\n"
      FAILED="${FAILED} ${pkg}"
    fi
    return "$fail"
  fi

  # --- install-path containment ---------------------------------------------
  # Everything belongs under /opt/rocm. The .pth is the sole exception: a
  # site directory is the only place the interpreter will read it from.
  local stray
  stray="$(echo "$paths" | grep -v '^\./opt/rocm/' \
    | grep -v '^\./usr/lib/python3/dist-packages/' || true)"
  if [ -n "$stray" ]; then
    echo "  ERROR: paths outside /opt/rocm:"; echo "$stray" | sed 's/^/      /'; fail=1
  fi

  # --- payload expectations --------------------------------------------------
  if [ "$files" -eq 0 ]; then
    echo "  ERROR: ${pkg} ships no files"; fail=1
  else
    local want
    for want in $(expected_contents "$pkg"); do
      if echo "$paths" | grep -qE "$want"; then
        echo "  contains ${want}: OK"
      else
        echo "  ERROR: ${pkg} is missing expected content ${want}"; fail=1
      fi
    done
  fi

  # --- SONAME chains ---------------------------------------------------------
  # A versioned library must be one real file plus symlinks. Duplicate regular
  # files make the loader map the library twice under different inodes (#43).
  local stem reals
  for stem in $(echo "$paths" | sed -n 's/.*\/\(lib[a-z0-9_+-]*\)\.so.*/\1/p' | sort -u); do
    reals="$(echo "$contents" | awk -v s="/${stem}.so" \
      '$1 !~ /^d/ && $1 !~ /^l/ && index($6, s) {n++} END {print n+0}')"
    if [ "$reals" -gt 1 ]; then
      echo "  ERROR: ${stem} ships ${reals} real files; the SONAME chain was flattened"
      fail=1
    fi
  done

  # --- executables -----------------------------------------------------------
  local badmode
  badmode="$(echo "$contents" | awk '$1 !~ /^d/ && $6 ~ /\/bin\// && $1 !~ /x/ {print $6}')"
  if [ -n "$badmode" ]; then
    echo "  ERROR: files under bin/ are not executable:"
    echo "$badmode" | sed 's/^/      /'; fail=1
  fi

  # --- no stock bundled SONAMEs in the sysdeps package -----------------------
  if [ "$pkg" = "amdrocm-vision-sysdeps" ]; then
    local stock
    stock="$(echo "$paths" \
      | grep -E '/lib(protobuf|protobuf-lite|turbojpeg|jpeg|lmdb|sndfile)\.so' || true)"
    if [ -n "$stock" ]; then
      echo "  ERROR: sysdeps ships un-isolated stock SONAMEs:"
      echo "$stock" | sed 's/^/      /'; fail=1
    fi
  fi

  if [ "$fail" -eq 0 ]; then
    echo "  => ${pkg}: PASS"
    SUMMARY="${SUMMARY}  PASS  ${pkg} (${files} files)\n"
  else
    echo "  => ${pkg}: FAIL"
    SUMMARY="${SUMMARY}  FAIL  ${pkg} (${files} files)\n"
    FAILED="${FAILED} ${pkg}"
  fi
  return "$fail"
}

command -v dpkg-deb >/dev/null 2>&1 || { echo "dpkg-deb not found"; exit 1; }

DEBS="$(find "$DEB_DIR" -maxdepth 2 -name '*.deb' | sort)"
if [ -z "$DEBS" ]; then
  echo "ERROR: no .deb files under ${DEB_DIR}"
  exit 1
fi
echo "Validating $(echo "$DEBS" | grep -c .) package(s) from ${DEB_DIR}"

for deb in $DEBS; do
  check_package "$deb" || true
done

echo "------------------------------------------------------------------"
echo "### cross-package checks"
OVERLAP_FAIL=0
HAS_PYDECODE=0
HAS_PYDECODE_TEST=0
# path -> owning package; a second owner is a dpkg overwrite on co-install.
declare -A PATH_OWNER
for deb in $DEBS; do
  pkg="$(dpkg-deb --field "$deb" Package 2>/dev/null || echo '')"
  [ -n "$pkg" ] || continue
  [ "$pkg" = "amdrocm-pydecode" ] && HAS_PYDECODE=1
  [ "$pkg" = "amdrocm-pydecode-test" ] && HAS_PYDECODE_TEST=1
  is_meta "$pkg" && continue
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    prev="${PATH_OWNER[$p]:-}"
    if [ -n "$prev" ] && [ "$prev" != "$pkg" ]; then
      echo "  ERROR: $p ships in both $prev and $pkg"
      OVERLAP_FAIL=1
    else
      PATH_OWNER[$p]="$pkg"
    fi
  done < <(dpkg-deb --contents "$deb" | awk '$1 !~ /^d/ {print $6}')
done
if [ "$OVERLAP_FAIL" -eq 0 ]; then
  echo "  no overlapping payload paths: OK"
else
  FAILED="${FAILED} overlapping-paths"
fi
if [ "$HAS_PYDECODE" -eq 1 ]; then
  echo "  amdrocm-pydecode produced: OK"
else
  echo "  ERROR: amdrocm-pydecode package was not produced"
  FAILED="${FAILED} missing-pydecode"
fi
if [ "$HAS_PYDECODE_TEST" -eq 1 ]; then
  echo "  amdrocm-pydecode-test produced: OK"
else
  echo "  ERROR: amdrocm-pydecode-test package was not produced"
  FAILED="${FAILED} missing-pydecode-test"
fi

echo "=================================================================="
echo "Package validation summary"
printf '%b' "$SUMMARY"
if [ -n "$FAILED" ]; then
  echo "FAILED:${FAILED}"
  exit 1
fi
echo "All packages passed."
