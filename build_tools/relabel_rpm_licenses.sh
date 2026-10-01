#!/usr/bin/env bash
#
# Narrow each RPM's License tag to exactly what its payload contains.
#
#   build_tools/relabel_rpm_licenses.sh <dir-with-rpms>
#
# CPackRPM has no per-component License override: it reads only the global
# CPACK_RPM_PACKAGE_LICENSE and writes the same tag into every package (see
# packaging/CMakeLists.txt). CPack sets that to the pack-wide superset so no
# package under-declares; this script runs after `cpack -G RPM` and rewrites
# each package's License preamble to the precise set for its contents, so the
# pure-MIT packages no longer over-declare.
#
# It edits the existing .rpm in place via rpmrebuild (needs rpmrebuild +
# rpmbuild), then re-queries %{LICENSE} and fails if the rewrite did not take —
# rpmrebuild has a known -p/--change-spec-preamble bug on older versions, so a
# silent no-op must be caught, not shipped.
set -euo pipefail

dir="${1:?usage: relabel_rpm_licenses.sh <dir-with-rpms>}"

command -v rpmrebuild >/dev/null 2>&1 || { echo "ERROR: rpmrebuild not found"; exit 1; }
command -v rpm        >/dev/null 2>&1 || { echo "ERROR: rpm not found"; exit 1; }

# License set per package, keyed off the renamed package (not the CPack
# component). Keep in sync with the licenses shipped under each package's
# share/doc/<pkg>/licenses/ (see third-party/ and top-level CMakeLists.txt).
license_for() {
  case "$1" in
    amdrocm-vision-sysdeps)
      # protobuf BSD-3, libjpeg-turbo IJG/BSD-3/Zlib, lmdb OpenLDAP, libsndfile LGPL-2.1.
      echo "BSD-3-Clause AND IJG AND Zlib AND OLDAP-2.8 AND LGPL-2.1-or-later" ;;
    amdrocm-rocal|amdrocm-roccv|amdrocm-pydecode)
      # MIT vision lib + bundled pybind11 (BSD-3) + dlpack (Apache-2.0)
      # (+ rapidjson MIT in rocAL, subsumed by MIT).
      echo "MIT AND BSD-3-Clause AND Apache-2.0" ;;
    *)
      # Vision libs, -devel/-test, pythonpath: own code only, all MIT.
      echo "MIT" ;;
  esac
}

shopt -s nullglob
rpms=("$dir"/*.rpm)
[ "${#rpms[@]}" -gt 0 ] || { echo "ERROR: no .rpm files in $dir"; exit 1; }

fail=0
for rpm in "${rpms[@]}"; do
  name="$(rpm -qp --queryformat '%{NAME}' "$rpm" 2>/dev/null || true)"
  [ -n "$name" ] || { echo "ERROR: cannot read NAME from $rpm"; fail=1; continue; }
  want="$(license_for "$name")"
  have="$(rpm -qp --queryformat '%{LICENSE}' "$rpm" 2>/dev/null || true)"
  if [ "$have" = "$want" ]; then
    echo "  ${name}: License already '${want}' — skipped"
    continue
  fi

  out="$(mktemp -d)"
  rpmrebuild --batch --package --directory="$out" \
    --change-spec-preamble="sed -e 's|^License:.*|License: ${want}|'" \
    "$rpm" >/dev/null

  built="$(find "$out" -name '*.rpm' -type f | head -1)"
  if [ -z "$built" ]; then
    echo "  ERROR: ${name}: rpmrebuild produced no package"; fail=1; rm -rf "$out"; continue
  fi
  got="$(rpm -qp --queryformat '%{LICENSE}' "$built" 2>/dev/null || true)"
  if [ "$got" != "$want" ]; then
    echo "  ERROR: ${name}: License is '${got}' after rebuild, expected '${want}'"; fail=1; rm -rf "$out"; continue
  fi
  mv -f "$built" "$rpm"
  rm -rf "$out"
  echo "  ${name}: '${have}' -> '${want}'"
done

[ "$fail" -eq 0 ] || { echo "relabel_rpm_licenses: FAILED"; exit 1; }
echo "relabel_rpm_licenses: OK"
