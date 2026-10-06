# CPack configuration for amdrocm-vision packages.
#
# Install layout mirrors /opt/rocm exactly — same as any other ROCm component:
#
#   lib/libopenvx.so, lib/librocal.so, lib/libroccv.so ...
#   lib/rocm_sysdeps/lib/libturbojpeg.so, libprotobuf.so, liblmdb.so, libsndfile.so
#   include/mivisionx/, include/rocal/, include/roccv/
#   lib/cmake/mivisionx/, lib/cmake/roccv/
#   share/mivisionx/, share/rocal/, share/roccv/
#   share/doc/mivisionx/, share/doc/rocal/, ...
#   bin/runvx
#
# Package hierarchy (from MIVisionX#1756). The ROCm <major>.<minor> from
# VISION_PACK_ROCM_VERSION is glued on, the way TheRock names
# amdrocm-runtime<major>.<minor>. The names below use 10.2 as an example.
# Two builds for different releases are different package names and can
# be installed together.
#
#   amdrocm-vision10.2         runtime meta
#   amdrocm-vision-sdk10.2     dev meta
#   amdrocm-vision-tests10.2   test meta
#
#   amdrocm-mivisionx10.2 / amdrocm-mivisionx-devel10.2 / amdrocm-mivisionx-test10.2
#   amdrocm-rocal10.2      / amdrocm-rocal-devel10.2      / amdrocm-rocal-test10.2
#   amdrocm-roccv10.2      / amdrocm-roccv-devel10.2       / amdrocm-roccv-test10.2
#   amdrocm-pydecode10.2                                / amdrocm-pydecode-test10.2

cmake_minimum_required(VERSION 3.21)
project(vision-pack-cpack NONE)

if(NOT DEFINED VISION_PACK_VERSION)
  set(VISION_PACK_VERSION "0.2.0" CACHE STRING "Package version")
endif()
if(NOT DEFINED VISION_PACK_ROCM_VERSION)
  set(VISION_PACK_ROCM_VERSION "10.2.0" CACHE STRING "ROCm SDK version")
endif()
if(NOT DEFINED VISION_PACK_BUILD_ID)
  set(VISION_PACK_BUILD_ID "0" CACHE STRING "CI build ID / run number")
endif()
if(NOT DEFINED VISION_PACK_STAGING_DIR)
  set(VISION_PACK_STAGING_DIR "${CMAKE_BINARY_DIR}/staging" CACHE PATH
    "Directory containing the installed vision libraries (mirrors /opt/rocm layout)")
endif()

set(VP_VER  "${VISION_PACK_VERSION}")
set(VP_ROCM "${VISION_PACK_ROCM_VERSION}")
# <major>.<minor>.<patch> -> <major>.<minor>, for example 10.2.0 -> 10.2.
# Matches amdrocm-runtime<major>.<minor> rather than a hyphenated suffix.
string(REGEX MATCH "^[0-9]+\\.[0-9]+" VP_ROCM_REL "${VP_ROCM}")
if(NOT VP_ROCM_REL)
  message(FATAL_ERROR
    "VISION_PACK_ROCM_VERSION must start with <major>.<minor>, got '${VP_ROCM}'")
endif()
# TheRock nightlies sort before the final release because of the tilde.
# For example, 10.2.0~DATE is older than 10.2.0. A trailing tilde on the
# lower bound accepts those versions.
set(VP_ROCM_MIN "${VP_ROCM}~")

# Debian: "name (>= ver)"    RPM: "name >= ver"
set(VP_DEB_RPP     "amdrocm-rpp${VP_ROCM_REL} (>= ${VP_ROCM_MIN})")
set(VP_DEB_RUNTIME "amdrocm-runtime${VP_ROCM_REL} (>= ${VP_ROCM_MIN})")
set(VP_DEB_DECODE  "amdrocm-decode${VP_ROCM_REL} (>= ${VP_ROCM_MIN})")
set(VP_DEB_JPEG    "amdrocm-jpeg${VP_ROCM_REL} (>= ${VP_ROCM_MIN})")
set(VP_DEB_HIPFILE "amdrocm-hipfile${VP_ROCM_REL} (>= ${VP_ROCM_MIN})")
set(VP_RPM_RPP     "amdrocm-rpp${VP_ROCM_REL} >= ${VP_ROCM_MIN}")
set(VP_RPM_RUNTIME "amdrocm-runtime${VP_ROCM_REL} >= ${VP_ROCM_MIN}")
set(VP_RPM_DECODE  "amdrocm-decode${VP_ROCM_REL} >= ${VP_ROCM_MIN}")
set(VP_RPM_JPEG    "amdrocm-jpeg${VP_ROCM_REL} >= ${VP_ROCM_MIN}")
set(VP_RPM_HIPFILE "amdrocm-hipfile${VP_ROCM_REL} >= ${VP_ROCM_MIN}")

set(VP_PKG_MIVISIONX      "amdrocm-mivisionx${VP_ROCM_REL}")
set(VP_PKG_MIVISIONX_DEV  "amdrocm-mivisionx-devel${VP_ROCM_REL}")
set(VP_PKG_MIVISIONX_TEST "amdrocm-mivisionx-test${VP_ROCM_REL}")
set(VP_PKG_ROCAL          "amdrocm-rocal${VP_ROCM_REL}")
set(VP_PKG_ROCAL_DEV      "amdrocm-rocal-devel${VP_ROCM_REL}")
set(VP_PKG_ROCAL_TEST     "amdrocm-rocal-test${VP_ROCM_REL}")
set(VP_PKG_ROCCV          "amdrocm-roccv${VP_ROCM_REL}")
set(VP_PKG_ROCCV_DEV      "amdrocm-roccv-devel${VP_ROCM_REL}")
set(VP_PKG_ROCCV_TEST     "amdrocm-roccv-test${VP_ROCM_REL}")
set(VP_PKG_PYDECODE       "amdrocm-pydecode${VP_ROCM_REL}")
set(VP_PKG_PYDECODE_TEST  "amdrocm-pydecode-test${VP_ROCM_REL}")
set(VP_PKG_SYSDEPS        "amdrocm-vision-sysdeps${VP_ROCM_REL}")
set(VP_PKG_PYTHONPATH     "amdrocm-vision-pythonpath${VP_ROCM_REL}")
set(VP_PKG_VISION         "amdrocm-vision${VP_ROCM_REL}")
set(VP_PKG_SDK            "amdrocm-vision-sdk${VP_ROCM_REL}")
set(VP_PKG_TESTS          "amdrocm-vision-tests${VP_ROCM_REL}")

# ---------------------------------------------------------------------------
# CPack global settings
# ---------------------------------------------------------------------------
set(CPACK_PACKAGE_NAME        "amdrocm-vision")
set(CPACK_PACKAGE_VERSION     "${VP_VER}")
set(CPACK_PACKAGE_VENDOR      "Advanced Micro Devices, Inc.")
set(CPACK_PACKAGE_CONTACT     "rocm-support@amd.com")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY
    "AMD ROCm Computer Vision extension pack (MIVisionX, rocAL, rocCV, rocPyDecode)")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE")

# TheRock installs each ROCm release under /opt/rocm/core-<major>.<minor>
# (for example /opt/rocm/core-10.2) and points /opt/rocm/{bin,include,lib}
# at one of them with alternatives. Vision files go in that same core tree
# so packages built for different releases do not own the same paths.
# /opt/rocm/lib still sees the selected release.
set(CPACK_PACKAGING_INSTALL_PREFIX "/opt/rocm/core-${VP_ROCM_REL}")

set(CPACK_COMPONENTS_ALL
    mivisionx mivisionx-dev mivisionx-test
    rocal      rocal-dev     rocal-test
    roccv      roccv-dev     roccv-test
    rocpydecode               rocpydecode-test
    rocm-sysdeps-vision
    pythonpath
)

# ---------------------------------------------------------------------------
# Component descriptions
# ---------------------------------------------------------------------------
set(CPACK_COMPONENT_MIVISIONX_DISPLAY_NAME      "AMD MIVisionX runtime")
set(CPACK_COMPONENT_MIVISIONX_DESCRIPTION
    "OpenVX engine (libopenvx, libvxu) and RPP extension (libvx_rpp).")
set(CPACK_COMPONENT_MIVISIONX_DEV_DISPLAY_NAME  "AMD MIVisionX development")
set(CPACK_COMPONENT_MIVISIONX_DEV_DESCRIPTION   "Headers, cmake config, and samples.")
set(CPACK_COMPONENT_ROCAL_DISPLAY_NAME          "AMD rocAL runtime")
set(CPACK_COMPONENT_ROCAL_DESCRIPTION           "ROCm Augmentation Library + Python bindings.")
set(CPACK_COMPONENT_ROCAL_DEV_DISPLAY_NAME      "AMD rocAL development")
set(CPACK_COMPONENT_ROCAL_DEV_DESCRIPTION       "Headers and cmake config.")
set(CPACK_COMPONENT_ROCCV_DISPLAY_NAME          "AMD rocCV runtime")
set(CPACK_COMPONENT_ROCCV_DESCRIPTION           "GPU image processing library + Python bindings.")
set(CPACK_COMPONENT_ROCCV_DEV_DISPLAY_NAME      "AMD rocCV development")
set(CPACK_COMPONENT_ROCCV_DEV_DESCRIPTION       "Headers and cmake config.")
set(CPACK_COMPONENT_ROCPYDECODE_DISPLAY_NAME    "AMD rocPyDecode")
set(CPACK_COMPONENT_ROCPYDECODE_DESCRIPTION     "Python bindings for rocDecode/rocJPEG.")
set(CPACK_COMPONENT_ROCM_SYSDEPS_VISION_DISPLAY_NAME "AMD rocCV bundled runtime deps")
set(CPACK_COMPONENT_ROCM_SYSDEPS_VISION_DESCRIPTION
    "Bundled runtime libs (libturbojpeg, libprotobuf, liblmdb, libsndfile) "
    "installed into lib/rocm_sysdeps/lib/ alongside existing ROCm sysdeps.")
set(CPACK_COMPONENT_PYTHONPATH_DISPLAY_NAME     "AMD ROCm vision Python path")
set(CPACK_COMPONENT_PYTHONPATH_DESCRIPTION
    "Registers /opt/rocm/lib on the Python path (.pth) so the vision Python "
    "modules import without manual PYTHONPATH setup.")
set(CPACK_COMPONENT_PYTHONPATH-RPM_DISPLAY_NAME "AMD ROCm vision Python path")
set(CPACK_COMPONENT_PYTHONPATH-RPM_DESCRIPTION
    "Registers /opt/rocm/lib on the Python 3.12 path (.pth) so the vision Python "
    "modules import without manual PYTHONPATH setup.")

# ---------------------------------------------------------------------------
# Install rules — paths match /opt/rocm exactly
# ---------------------------------------------------------------------------

# install(DIRECTORY ... FILES_MATCHING) still creates every subdirectory it
# walks, so each runtime package shipped the other components' trees empty.
# With only amdrocm-roccv installed, `import amd.rocal` then succeeds as a
# namespace package (#55). Glob the files instead. Configure runs after the
# staging tree is unpacked, and install(FILES) keeps SONAME symlinks as
# symlinks.
function(vision_pack_install_matched component destination)
  file(GLOB _matched LIST_DIRECTORIES false ${ARGN})
  if(NOT _matched)
    message(FATAL_ERROR
      "vision-pack: component '${component}' matched no files for '${destination}'")
  endif()
  install(FILES ${_matched}
    DESTINATION "${destination}"
    COMPONENT "${component}"
  )
endfunction()

# --- MIVisionX runtime: lib/*.so + bin/runvx ---
vision_pack_install_matched(mivisionx lib
  "${VISION_PACK_STAGING_DIR}/lib/libopenvx.so*"
  "${VISION_PACK_STAGING_DIR}/lib/libvxu.so*"
  "${VISION_PACK_STAGING_DIR}/lib/libvx_rpp.so*"
)
install(PROGRAMS "${VISION_PACK_STAGING_DIR}/bin/runvx"
    DESTINATION bin COMPONENT mivisionx OPTIONAL
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/mivisionx/LICENSE.txt"
    DESTINATION "share/doc/${VP_PKG_MIVISIONX}" COMPONENT mivisionx OPTIONAL
)
# --- MIVisionX dev: include/mivisionx/ + lib/cmake/ + share/mivisionx/ ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/include/mivisionx"
    DESTINATION include COMPONENT mivisionx-dev
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/cmake/mivisionx"
    DESTINATION lib/cmake COMPONENT mivisionx-dev OPTIONAL
)
# Transitional find-module shim: upstream ships no MIVisionXConfig.cmake
# (MIVisionX#1761), so vision-pack provides FindMIVisionX.cmake in lib/cmake so
# downstream find_package(MIVisionX) works. Remove once upstream exports land.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../cmake/shims/FindMIVisionX.cmake"
    DESTINATION lib/cmake COMPONENT mivisionx-dev
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/mivisionx"
    DESTINATION share COMPONENT mivisionx-dev OPTIONAL
    PATTERN test EXCLUDE
)
# --- MIVisionX test ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/mivisionx/test"
    DESTINATION share/mivisionx COMPONENT mivisionx-test OPTIONAL
)

# --- rocAL runtime: lib/librocal.so* + Python binding ---
vision_pack_install_matched(rocal lib
  "${VISION_PACK_STAGING_DIR}/lib/librocal.so*"
  "${VISION_PACK_STAGING_DIR}/lib/rocal_pybind*.so"
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/amd"
    DESTINATION lib COMPONENT rocal OPTIONAL
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/rocal/LICENSE.txt"
    DESTINATION "share/doc/${VP_PKG_ROCAL}" COMPONENT rocal OPTIONAL
)
# Licenses of the bundled header-only deps compiled into rocAL (staged by
# third-party/): pybind11, dlpack, rapidjson.
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/doc/amdrocm-rocal/licenses"
    DESTINATION "share/doc/${VP_PKG_ROCAL}" COMPONENT rocal OPTIONAL
)
# --- rocAL dev: include/rocal/ ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/include/rocal"
    DESTINATION include COMPONENT rocal-dev
)
# Transitional find-module shim: upstream ships no rocalConfig.cmake (rocAL#514),
# so vision-pack provides Findrocal.cmake. Remove once upstream exports land.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../cmake/shims/Findrocal.cmake"
    DESTINATION lib/cmake COMPONENT rocal-dev
)
# --- rocAL test ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/rocal/test"
    DESTINATION share/rocal COMPONENT rocal-test OPTIONAL
)

# --- rocCV runtime: lib/libroccv.so* + Python binding + type stub ---
vision_pack_install_matched(roccv lib
  "${VISION_PACK_STAGING_DIR}/lib/libroccv.so*"
  "${VISION_PACK_STAGING_DIR}/lib/rocpycv*.so"
  "${VISION_PACK_STAGING_DIR}/lib/rocpycv.pyi"
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/roccv/LICENSE.txt"
    DESTINATION "share/doc/${VP_PKG_ROCCV}" COMPONENT roccv OPTIONAL
)
# Licenses of the vendored deps compiled into rocpycv (staged by top-level
# CMakeLists): pybind11, dlpack.
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/doc/amdrocm-roccv/licenses"
    DESTINATION "share/doc/${VP_PKG_ROCCV}" COMPONENT roccv OPTIONAL
)
# --- rocCV dev: include/roccv/ + lib/cmake/roccv/ ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/include/roccv"
    DESTINATION include COMPONENT roccv-dev
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/cmake/roccv"
    DESTINATION lib/cmake COMPONENT roccv-dev OPTIONAL
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/roccv/samples"
    DESTINATION share/roccv COMPONENT roccv-dev OPTIONAL
)
# --- rocCV test ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/roccv/test"
    DESTINATION share/roccv COMPONENT roccv-test OPTIONAL
)

# --- rocPyDecode: Python extension modules ---
# rocPyDecode's upstream install rules carry no CMake COMPONENT tags
# (rocPyDecode#285), so we can't rely on component-filtered installs. Instead we
# split by PATH here at the packaging layer: runtime .so's → rocpydecode, and
# share/rocpydecode/tests → rocpydecode-test (below). No submodule patch needed.
# The pyRoc* trees are this component's own packages, so they install whole.
vision_pack_install_matched(rocpydecode lib
  "${VISION_PACK_STAGING_DIR}/lib/rocpydecode*.so"
  "${VISION_PACK_STAGING_DIR}/lib/rocpyjpegdecode*.so"
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/pyRocVideoDecode"
    DESTINATION lib COMPONENT rocpydecode
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/pyRocJpegDecode"
    DESTINATION lib COMPONENT rocpydecode
)
# rocPyDecode's own LICENSE + vendored dep licenses (pybind11, dlpack) compiled
# into rocpydecode/rocpyjpegdecode (staged by top-level CMakeLists).
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/amdrocm-pydecode/LICENSE.txt"
    DESTINATION "share/doc/${VP_PKG_PYDECODE}" COMPONENT rocpydecode OPTIONAL
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/doc/amdrocm-pydecode/licenses"
    DESTINATION "share/doc/${VP_PKG_PYDECODE}" COMPONENT rocpydecode OPTIONAL
)
# --- rocPyDecode test ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/rocpydecode/tests"
    DESTINATION share/rocpydecode COMPONENT rocpydecode-test OPTIONAL
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/rocpyjpegdecode/tests"
    DESTINATION share/rocpyjpegdecode COMPONENT rocpydecode-test OPTIONAL
)

# --- Bundled runtime deps → lib/rocm_sysdeps/lib/ (same as ROCm sysdeps) ---
# These are installed alongside the existing zlib, bzip2 etc. in rocm_sysdeps.
# The build stage rewrites their SONAMEs to private *-rocm-vision names for
# side-by-side isolation from host copies (build_tools/rewrite_sonames.py, #4),
# so the patterns match the renamed files, not the stock upstream names.
vision_pack_install_matched(rocm-sysdeps-vision lib/rocm_sysdeps/lib
  "${VISION_PACK_STAGING_DIR}/lib/rocm_sysdeps/lib/libturbojpeg-rocm-vision.so*"
  "${VISION_PACK_STAGING_DIR}/lib/rocm_sysdeps/lib/libjpeg-rocm-vision.so*"
  "${VISION_PACK_STAGING_DIR}/lib/rocm_sysdeps/lib/libprotobuf-rocm-vision.so*"
  "${VISION_PACK_STAGING_DIR}/lib/rocm_sysdeps/lib/libprotobuf-lite-rocm-vision.so*"
  "${VISION_PACK_STAGING_DIR}/lib/rocm_sysdeps/lib/liblmdb-rocm-vision.so*"
  "${VISION_PACK_STAGING_DIR}/lib/rocm_sysdeps/lib/libsndfile-rocm-vision.so*"
)
# Licenses of the bundled deps shipped in this package (staged by third-party/).
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/doc/amdrocm-vision-sysdeps/licenses"
    DESTINATION "share/doc/${VP_PKG_SYSDEPS}" COMPONENT rocm-sysdeps-vision OPTIONAL
)

# --- Python path registration (.pth) → host site-packages (#4, #67, #79) ---
# The vision Python modules (rocal_pybind, rocpycv, rocpydecode, ...) install
# flat into /opt/rocm/lib, which is not on the interpreter's sys.path, so users
# otherwise need `export PYTHONPATH=/opt/rocm/lib`. A .pth file adds that dir to
# sys.path automatically — but only when it lives in a *real* site directory, so
# we install it to the host's absolute site directory, not under /opt/rocm. One
# dedicated component owns the file so the three runtime packages can each
# depend on it without a file-overwrite conflict.
# Debian/Ubuntu read /usr/lib/python3/dist-packages. RHEL-family Python 3.12
# reads /usr/lib/python3.12/site-packages, and the modules are CPython 3.12
# builds, so the RPM ships that path as a packaged file. A %post that writes
# an untracked .pth is not used: rpm would not own the file, and the platform
# python3 (3.9 on RHEL 9) is not the interpreter that loads the modules.
# cpack_project_config.cmake puts pythonpath in the DEB and pythonpath-rpm
# in the RPM, so the .deb does not gain the 3.12 path and the RPM does not
# own Debian's directories.
# Filename carries the ROCm release (for example amdrocm-vision10.2.pth) so
# two releases can both own a .pth. Each file lists /opt/rocm/lib, which
# alternatives point at the selected core.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/python/amdrocm-vision.pth"
    DESTINATION /usr/lib/python3/dist-packages
    RENAME "amdrocm-vision${VP_ROCM_REL}.pth"
    COMPONENT pythonpath
)
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/python/amdrocm-vision.pth"
    DESTINATION /usr/lib/python3.12/site-packages
    RENAME "amdrocm-vision${VP_ROCM_REL}.pth"
    COMPONENT pythonpath-rpm
)

# ---------------------------------------------------------------------------
# DEB settings
# ---------------------------------------------------------------------------
set(CPACK_DEB_COMPONENT_INSTALL ON)
set(CPACK_DEBIAN_PACKAGE_RELEASE    "${VISION_PACK_BUILD_ID}")
set(CPACK_DEBIAN_PACKAGE_SECTION    "devel")
set(CPACK_DEBIAN_PACKAGE_PRIORITY   "optional")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "ROCm Engineering <rocm-support@amd.com>")
set(CPACK_DEBIAN_PACKAGE_HOMEPAGE   "https://github.com/kiritigowda/vision-pack")

set(CPACK_DEBIAN_MIVISIONX_PACKAGE_NAME            "${VP_PKG_MIVISIONX}")
set(CPACK_DEBIAN_MIVISIONX-DEV_PACKAGE_NAME        "${VP_PKG_MIVISIONX_DEV}")
set(CPACK_DEBIAN_MIVISIONX-TEST_PACKAGE_NAME       "${VP_PKG_MIVISIONX_TEST}")
set(CPACK_DEBIAN_ROCAL_PACKAGE_NAME                "${VP_PKG_ROCAL}")
set(CPACK_DEBIAN_ROCAL-DEV_PACKAGE_NAME            "${VP_PKG_ROCAL_DEV}")
set(CPACK_DEBIAN_ROCAL-TEST_PACKAGE_NAME           "${VP_PKG_ROCAL_TEST}")
set(CPACK_DEBIAN_ROCCV_PACKAGE_NAME                "${VP_PKG_ROCCV}")
set(CPACK_DEBIAN_ROCCV-DEV_PACKAGE_NAME            "${VP_PKG_ROCCV_DEV}")
set(CPACK_DEBIAN_ROCCV-TEST_PACKAGE_NAME           "${VP_PKG_ROCCV_TEST}")
set(CPACK_DEBIAN_ROCPYDECODE_PACKAGE_NAME          "${VP_PKG_PYDECODE}")
set(CPACK_DEBIAN_ROCPYDECODE-TEST_PACKAGE_NAME     "${VP_PKG_PYDECODE_TEST}")
set(CPACK_DEBIAN_ROCM-SYSDEPS-VISION_PACKAGE_NAME  "${VP_PKG_SYSDEPS}")
set(CPACK_DEBIAN_PYTHONPATH_PACKAGE_NAME           "${VP_PKG_PYTHONPATH}")

# Runtime deps name the versioned packages the ROCm repository publishes:
# amdrocm-runtime<major>.<minor>, for example amdrocm-runtime10.2, not
# hip-runtime-amd or the unversioned alias. The unversioned aliases exist,
# but a nightly version such as 10.2.0~DATE does not satisfy >= 10.2.0,
# and a side-by-side SDK does not install those aliases.
# The three Python-binding packages pull in the pythonpath package so
# `import rocal` / `import rocpycv` / `import rocpydecode` work with no PYTHONPATH.
set(CPACK_DEBIAN_MIVISIONX_PACKAGE_DEPENDS
    "${VP_DEB_RPP}, ${VP_DEB_RUNTIME}")
set(CPACK_DEBIAN_ROCAL_PACKAGE_DEPENDS
    "${VP_PKG_MIVISIONX} (>= ${VP_VER}), ${VP_PKG_SYSDEPS} (>= ${VP_VER}), ${VP_PKG_PYTHONPATH} (>= ${VP_VER}), ${VP_DEB_DECODE}, ${VP_DEB_JPEG}, ${VP_DEB_HIPFILE}")
set(CPACK_DEBIAN_ROCCV_PACKAGE_DEPENDS
    "${VP_PKG_PYTHONPATH} (>= ${VP_VER}), ${VP_DEB_RUNTIME}")
set(CPACK_DEBIAN_ROCPYDECODE_PACKAGE_DEPENDS
    "${VP_PKG_PYTHONPATH} (>= ${VP_VER}), ${VP_DEB_DECODE}, ${VP_DEB_JPEG}")

# A -devel package is useless without the runtime it links against, and a -test
# package without the runtime it exercises. The C/C++ test sources also need
# the headers, CMake config, and samples from the matching -devel package.
# rocAL headers include MIVisionX headers, so its -devel also pulls the
# MIVisionX devel package.
set(CPACK_DEBIAN_MIVISIONX-DEV_PACKAGE_DEPENDS
    "${VP_PKG_MIVISIONX} (>= ${VP_VER})")
set(CPACK_DEBIAN_MIVISIONX-TEST_PACKAGE_DEPENDS
    "${VP_PKG_MIVISIONX} (>= ${VP_VER}), ${VP_PKG_MIVISIONX_DEV} (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCAL-DEV_PACKAGE_DEPENDS
    "${VP_PKG_ROCAL} (>= ${VP_VER}), ${VP_PKG_MIVISIONX_DEV} (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCAL-TEST_PACKAGE_DEPENDS
    "${VP_PKG_ROCAL} (>= ${VP_VER}), ${VP_PKG_ROCAL_DEV} (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCCV-DEV_PACKAGE_DEPENDS
    "${VP_PKG_ROCCV} (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCCV-TEST_PACKAGE_DEPENDS
    "${VP_PKG_ROCCV} (>= ${VP_VER}), ${VP_PKG_ROCCV_DEV} (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCPYDECODE-TEST_PACKAGE_DEPENDS
    "${VP_PKG_PYDECODE} (>= ${VP_VER})")

# ---------------------------------------------------------------------------
# RPM settings
# ---------------------------------------------------------------------------
set(CPACK_RPM_COMPONENT_INSTALL ON)
set(CPACK_RPM_PACKAGE_RELEASE   "${VISION_PACK_BUILD_ID}")
set(CPACK_RPM_PACKAGE_GROUP     "Development/Libraries")
# RPM License tag — default for the MIT-only packages (the vision libraries and
# all -devel/-test/pythonpath packages). Stock CPack has no per-component License
# override: CPackRPM reads only this global CPACK_RPM_PACKAGE_LICENSE (its
# per-component spec-header fallback covers REQUIRES/PROVIDES/etc. but not
# LICENSE), and CPACK_PROJECT_CONFIG_FILE is per-generator, not per-component. So
# the packages that bundle third-party code (amdrocm-vision-sysdeps and
# amdrocm-rocal/roccv/pydecode) are re-emitted by package.yml in extra
# `cpack -G RPM` passes that override this with their precise license set, and
# build_tools/verify_rpm_licenses.sh asserts every package's final tag. Keeping
# the default at MIT means a plain `cpack -G RPM` (no override passes) still gives
# the correct tag for every MIT package. Per-package license *texts* ship under
# each package's share/doc/<pkg>/licenses/ (see third-party/ and top-level
# CMakeLists).
set(CPACK_RPM_PACKAGE_LICENSE "MIT")
set(CPACK_RPM_PACKAGE_URL       "https://github.com/kiritigowda/vision-pack")

set(CPACK_RPM_MIVISIONX_PACKAGE_NAME            "${VP_PKG_MIVISIONX}")
set(CPACK_RPM_MIVISIONX-DEV_PACKAGE_NAME        "${VP_PKG_MIVISIONX_DEV}")
set(CPACK_RPM_MIVISIONX-TEST_PACKAGE_NAME       "${VP_PKG_MIVISIONX_TEST}")
set(CPACK_RPM_ROCAL_PACKAGE_NAME                "${VP_PKG_ROCAL}")
set(CPACK_RPM_ROCAL-DEV_PACKAGE_NAME            "${VP_PKG_ROCAL_DEV}")
set(CPACK_RPM_ROCAL-TEST_PACKAGE_NAME           "${VP_PKG_ROCAL_TEST}")
set(CPACK_RPM_ROCCV_PACKAGE_NAME                "${VP_PKG_ROCCV}")
set(CPACK_RPM_ROCCV-DEV_PACKAGE_NAME            "${VP_PKG_ROCCV_DEV}")
set(CPACK_RPM_ROCCV-TEST_PACKAGE_NAME           "${VP_PKG_ROCCV_TEST}")
set(CPACK_RPM_ROCPYDECODE_PACKAGE_NAME          "${VP_PKG_PYDECODE}")
set(CPACK_RPM_ROCPYDECODE-TEST_PACKAGE_NAME     "${VP_PKG_PYDECODE_TEST}")
set(CPACK_RPM_ROCM-SYSDEPS-VISION_PACKAGE_NAME  "${VP_PKG_SYSDEPS}")
# Same package name as the Debian pythonpath component. The RPM generator
# packages pythonpath-rpm instead (see cpack_project_config.cmake).
set(CPACK_RPM_PYTHONPATH-RPM_PACKAGE_NAME       "${VP_PKG_PYTHONPATH}")
set(CPACK_RPM_PYTHONPATH-RPM_PACKAGE_REQUIRES   "python3.12")
# Do not own Python's site directories. python3.12 already does, and owning
# them makes this package conflict with the interpreter package. The .pth
# itself stays in %files, so rpm -e removes it.
# CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST_ADDITION is appended as one quoted
# element, so extra paths set that way never match. Replace the builtin
# omit list and add the Python 3.12 directories to it.
set(CPACK_RPM_EXCLUDE_FROM_AUTO_FILELIST
    /etc /etc/init.d /usr /usr/bin
    /usr/include /usr/lib /usr/libx32 /usr/lib64
    /usr/share /usr/share/aclocal /usr/share/doc
    /usr/lib/python3.12
    /usr/lib/python3.12/site-packages
)

# Requires mirror the DEB Depends above. Without them the RPMs declared no
# dependencies at all and would install onto a host with no ROCm present.
set(CPACK_RPM_MIVISIONX_PACKAGE_REQUIRES
    "${VP_RPM_RPP}, ${VP_RPM_RUNTIME}")
set(CPACK_RPM_ROCAL_PACKAGE_REQUIRES
    "${VP_PKG_MIVISIONX} >= ${VP_VER}, ${VP_PKG_SYSDEPS} >= ${VP_VER}, ${VP_PKG_PYTHONPATH} >= ${VP_VER}, ${VP_RPM_DECODE}, ${VP_RPM_JPEG}, ${VP_RPM_HIPFILE}")
set(CPACK_RPM_ROCCV_PACKAGE_REQUIRES
    "${VP_PKG_PYTHONPATH} >= ${VP_VER}, ${VP_RPM_RUNTIME}")
set(CPACK_RPM_ROCPYDECODE_PACKAGE_REQUIRES
    "${VP_PKG_PYTHONPATH} >= ${VP_VER}, ${VP_RPM_DECODE}, ${VP_RPM_JPEG}")
set(CPACK_RPM_MIVISIONX-DEV_PACKAGE_REQUIRES
    "${VP_PKG_MIVISIONX} >= ${VP_VER}")
set(CPACK_RPM_MIVISIONX-TEST_PACKAGE_REQUIRES
    "${VP_PKG_MIVISIONX} >= ${VP_VER}, ${VP_PKG_MIVISIONX_DEV} >= ${VP_VER}")
set(CPACK_RPM_ROCAL-DEV_PACKAGE_REQUIRES
    "${VP_PKG_ROCAL} >= ${VP_VER}, ${VP_PKG_MIVISIONX_DEV} >= ${VP_VER}")
set(CPACK_RPM_ROCAL-TEST_PACKAGE_REQUIRES
    "${VP_PKG_ROCAL} >= ${VP_VER}, ${VP_PKG_ROCAL_DEV} >= ${VP_VER}")
set(CPACK_RPM_ROCCV-DEV_PACKAGE_REQUIRES
    "${VP_PKG_ROCCV} >= ${VP_VER}")
set(CPACK_RPM_ROCCV-TEST_PACKAGE_REQUIRES
    "${VP_PKG_ROCCV} >= ${VP_VER}, ${VP_PKG_ROCCV_DEV} >= ${VP_VER}")
set(CPACK_RPM_ROCPYDECODE-TEST_PACKAGE_REQUIRES
    "${VP_PKG_PYDECODE} >= ${VP_VER}")

# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------
set(CPACK_GENERATOR "DEB;RPM;TGZ")
set(CPACK_TGZ_COMPONENT_INSTALL ON)
# Loaded once per generator. For RPM it swaps the pythonpath component.
set(CPACK_PROJECT_CONFIG_FILE
    "${CMAKE_CURRENT_SOURCE_DIR}/cpack_project_config.cmake")

include(CPack)

# ---------------------------------------------------------------------------
# Meta-packages: DEB via equivs, RPM via rpmbuild
# ---------------------------------------------------------------------------
# Templates stay unversioned on disk. The configured Package/Name fields
# append @VP_ROCM_REL@, and the output files use that full name.
set(_vision_meta_bases amdrocm-vision amdrocm-vision-sdk amdrocm-vision-tests)
set(_vision_metas "")
foreach(_base ${_vision_meta_bases})
  set(_meta "${_base}${VP_ROCM_REL}")
  list(APPEND _vision_metas "${_meta}")
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/meta/${_base}.control.in"
    "${CMAKE_CURRENT_BINARY_DIR}/meta/${_meta}.control"
    @ONLY
  )
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/meta/${_base}.spec.in"
    "${CMAKE_CURRENT_BINARY_DIR}/meta/${_meta}.spec"
    @ONLY
  )
endforeach()

find_program(EQUIVS_BUILD equivs-build)
find_program(RPMBUILD rpmbuild)

set(_meta_build_cmds "")
if(EQUIVS_BUILD)
  # equivs-build produces one .deb from the first Package: stanza of a control
  # file, so each meta-package needs its own control file.
  foreach(_meta ${_vision_metas})
    list(APPEND _meta_build_cmds
      COMMAND ${EQUIVS_BUILD} "${CMAKE_CURRENT_BINARY_DIR}/meta/${_meta}.control")
  endforeach()
endif()
if(RPMBUILD)
  # rpmbuild writes <_topdir>/RPMS/noarch/*.rpm. Copy next to the control
  # files so the packaging workflow can collect them with the component RPMs.
  list(APPEND _meta_build_cmds
    COMMAND ${CMAKE_COMMAND} -E make_directory
      "${CMAKE_CURRENT_BINARY_DIR}/rpmbuild/BUILD"
      "${CMAKE_CURRENT_BINARY_DIR}/rpmbuild/RPMS"
      "${CMAKE_CURRENT_BINARY_DIR}/rpmbuild/SOURCES"
      "${CMAKE_CURRENT_BINARY_DIR}/rpmbuild/SPECS"
      "${CMAKE_CURRENT_BINARY_DIR}/rpmbuild/SRPMS")
  foreach(_meta ${_vision_metas})
    list(APPEND _meta_build_cmds
      COMMAND ${RPMBUILD} -bb
        --define "_topdir ${CMAKE_CURRENT_BINARY_DIR}/rpmbuild"
        "${CMAKE_CURRENT_BINARY_DIR}/meta/${_meta}.spec")
  endforeach()
  list(APPEND _meta_build_cmds
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${CMAKE_CURRENT_BINARY_DIR}/rpmbuild/RPMS"
      "${CMAKE_CURRENT_BINARY_DIR}/meta/rpms")
endif()
if(_meta_build_cmds)
  add_custom_target(package-meta-vision
    ${_meta_build_cmds}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/meta"
    COMMENT "Building amdrocm-vision, -sdk, -tests meta-packages (DEB/RPM)"
  )
endif()
