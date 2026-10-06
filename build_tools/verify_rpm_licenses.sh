#!/usr/bin/env bash
#
# Assert each RPM's License tag names exactly the licenses its payload carries.
#
#   build_tools/verify_rpm_licenses.sh <dir-with-rpms>
#
# CPackRPM has no per-component License override: it reads only the global
# CPACK_RPM_PACKAGE_LICENSE and writes the same tag into every package. So
# package.yml builds all RPMs once as MIT, then re-emits the packages that
# bundle third-party code in extra `cpack -G RPM` passes (restricted with
# CPACK_COMPONENTS_ALL) that stamp their precise license set, overwriting just
# those RPMs. This script is the guard: if a restricted pass ever fails to
# restrict (and stamps the wrong license onto every package) or a bundling
# package is missed, the mismatch fails CI instead of shipping.
#
# license_for() is the source of truth; keep it in sync with the passes in
# package.yml and the texts shipped under each package's share/doc/<pkg>/licenses/.
set -euo pipefail

dir="${1:?usage: verify_rpm_licenses.sh <dir-with-rpms>}"
command -v rpm >/dev/null 2>&1 || { echo "ERROR: rpm not found"; exit 1; }

license_for() {
  # The RPM name carries the ROCm <major>.<minor>, for example
  # amdrocm-rocal10.2. The license set depends on the component, not the release.
  local base
  base="$(printf '%s\n' "$1" | sed -E 's/[0-9]+\.[0-9]+$//')"
  case "$base" in
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
    echo "  ${name}: License '${have}' OK"
  else
    echo "  ERROR: ${name}: License is '${have}', expected '${want}'"; fail=1
  fi
done

[ "$fail" -eq 0 ] || { echo "verify_rpm_licenses: FAILED"; exit 1; }
echo "verify_rpm_licenses: OK"
