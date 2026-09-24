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
# Package hierarchy (from MIVisionX#1756):
#   amdrocm-vision         runtime meta
#   amdrocm-vision-sdk     dev meta
#   amdrocm-vision-tests   test meta
#
#   amdrocm-mivisionx / amdrocm-mivisionx-devel / amdrocm-mivisionx-test
#   amdrocm-rocal      / amdrocm-rocal-devel      / amdrocm-rocal-test
#   amdrocm-roccv      / amdrocm-roccv-devel       / amdrocm-roccv-test
#   amdrocm-pydecode                            / amdrocm-pydecode-test

cmake_minimum_required(VERSION 3.21)
project(vision-pack-cpack NONE)

if(NOT DEFINED VISION_PACK_VERSION)
  set(VISION_PACK_VERSION "0.1.0" CACHE STRING "Package version")
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

# Install directly into /opt/rocm — no new top-level dirs
set(CPACK_PACKAGING_INSTALL_PREFIX "/opt/rocm")

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

# ---------------------------------------------------------------------------
# Install rules — paths match /opt/rocm exactly
# ---------------------------------------------------------------------------

# --- MIVisionX runtime: lib/*.so + bin/runvx ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/"
    DESTINATION lib COMPONENT mivisionx
    FILES_MATCHING
      PATTERN "libopenvx.so*"
      PATTERN "libvxu.so*"
      PATTERN "libvx_rpp.so*"
)
install(PROGRAMS "${VISION_PACK_STAGING_DIR}/bin/runvx"
    DESTINATION bin COMPONENT mivisionx OPTIONAL
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/mivisionx/LICENSE.txt"
    DESTINATION share/doc/amdrocm-mivisionx COMPONENT mivisionx OPTIONAL
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
)
# --- MIVisionX test ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/mivisionx/test"
    DESTINATION share/mivisionx COMPONENT mivisionx-test OPTIONAL
)

# --- rocAL runtime: lib/librocal.so* + Python binding ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/"
    DESTINATION lib COMPONENT rocal
    FILES_MATCHING
      PATTERN "librocal.so*"
      PATTERN "rocal_pybind*.so"
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/amd"
    DESTINATION lib COMPONENT rocal OPTIONAL
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/rocal/LICENSE.txt"
    DESTINATION share/doc/amdrocm-rocal COMPONENT rocal OPTIONAL
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
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/"
    DESTINATION lib COMPONENT roccv
    FILES_MATCHING
      PATTERN "libroccv.so*"
      PATTERN "rocpycv*.so"
      PATTERN "rocpycv.pyi"
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/roccv/LICENSE.txt"
    DESTINATION share/doc/amdrocm-roccv COMPONENT roccv OPTIONAL
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
# rocpydecode is built best-effort in CI (upstream-blocked on rocPyDecode#290);
# if its build is skipped these globs match nothing and the component packages
# empty rather than failing.
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/"
    DESTINATION lib COMPONENT rocpydecode
    FILES_MATCHING
      PATTERN "rocpydecode*.so"
      PATTERN "rocpyjpegdecode*.so"
      PATTERN "pyRocVideoDecode/*"
      PATTERN "pyRocJpegDecode/*"
)
# --- rocPyDecode test ---
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/rocpydecode/tests"
    DESTINATION share/rocpydecode COMPONENT rocpydecode-test OPTIONAL
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/rocpyjpegdecode/tests"
    DESTINATION share/rocpydecode COMPONENT rocpydecode-test OPTIONAL
)

# --- Bundled runtime deps → lib/rocm_sysdeps/lib/ (same as ROCm sysdeps) ---
# These are installed alongside the existing zlib, bzip2 etc. in rocm_sysdeps.
# The build stage rewrites their SONAMEs to private *-rocm-vision names for
# side-by-side isolation from host copies (build_tools/rewrite_sonames.py, #4),
# so the patterns match the renamed files, not the stock upstream names.
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/rocm_sysdeps/lib/"
    DESTINATION lib/rocm_sysdeps/lib COMPONENT rocm-sysdeps-vision
    FILES_MATCHING
      PATTERN "libturbojpeg-rocm-vision.so*"
      PATTERN "libjpeg-rocm-vision.so*"
      PATTERN "libprotobuf-rocm-vision.so*"
      PATTERN "libprotobuf-lite-rocm-vision.so*"
      PATTERN "liblmdb-rocm-vision.so*"
      PATTERN "libsndfile-rocm-vision.so*"
)

# --- Python path registration (.pth) → host site-packages (#4) ---
# The vision Python modules (rocal_pybind, rocpycv, rocpydecode, ...) install
# flat into /opt/rocm/lib, which is not on the interpreter's sys.path, so users
# otherwise need `export PYTHONPATH=/opt/rocm/lib`. A .pth file adds that dir to
# sys.path automatically — but only when it lives in a *real* site directory, so
# we install it to the host's absolute dist-packages, not under /opt/rocm. One
# dedicated component owns the file so the three runtime packages can each
# depend on it without a dpkg file-overwrite conflict.
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/python/amdrocm-vision.pth"
    DESTINATION /usr/lib/python3/dist-packages
    COMPONENT pythonpath
)

# ---------------------------------------------------------------------------
# DEB settings
# ---------------------------------------------------------------------------
set(CPACK_DEB_COMPONENT_INSTALL ON)
set(CPACK_DEBIAN_PACKAGE_RELEASE    "${VISION_PACK_BUILD_ID}")
set(CPACK_DEBIAN_PACKAGE_SECTION    "devel")
set(CPACK_DEBIAN_PACKAGE_PRIORITY   "optional")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "ROCm Engineering <rocm-support@amd.com>")
set(CPACK_DEBIAN_PACKAGE_HOMEPAGE   "https://github.com/ROCm/vision-pack")

set(CPACK_DEBIAN_MIVISIONX_PACKAGE_NAME            "amdrocm-mivisionx")
set(CPACK_DEBIAN_MIVISIONX-DEV_PACKAGE_NAME        "amdrocm-mivisionx-devel")
set(CPACK_DEBIAN_MIVISIONX-TEST_PACKAGE_NAME       "amdrocm-mivisionx-test")
set(CPACK_DEBIAN_ROCAL_PACKAGE_NAME                "amdrocm-rocal")
set(CPACK_DEBIAN_ROCAL-DEV_PACKAGE_NAME            "amdrocm-rocal-devel")
set(CPACK_DEBIAN_ROCAL-TEST_PACKAGE_NAME           "amdrocm-rocal-test")
set(CPACK_DEBIAN_ROCCV_PACKAGE_NAME                "amdrocm-roccv")
set(CPACK_DEBIAN_ROCCV-DEV_PACKAGE_NAME            "amdrocm-roccv-devel")
set(CPACK_DEBIAN_ROCCV-TEST_PACKAGE_NAME           "amdrocm-roccv-test")
set(CPACK_DEBIAN_ROCPYDECODE_PACKAGE_NAME          "amdrocm-pydecode")
set(CPACK_DEBIAN_ROCPYDECODE-TEST_PACKAGE_NAME     "amdrocm-pydecode-test")
set(CPACK_DEBIAN_ROCM-SYSDEPS-VISION_PACKAGE_NAME  "amdrocm-vision-sysdeps")
set(CPACK_DEBIAN_PYTHONPATH_PACKAGE_NAME           "amdrocm-vision-pythonpath")

# Runtime deps — only the ROCm components; bundled C libs ship in sysdeps package.
# The three Python-binding packages pull in amdrocm-vision-pythonpath so
# `import rocal` / `import rocpycv` / `import rocpydecode` work with no PYTHONPATH.
set(CPACK_DEBIAN_MIVISIONX_PACKAGE_DEPENDS
    "amdrocm-rpp (>= ${VP_ROCM}), hip-runtime-amd (>= ${VP_ROCM})")
set(CPACK_DEBIAN_ROCAL_PACKAGE_DEPENDS
    "amdrocm-mivisionx (>= ${VP_VER}), amdrocm-vision-sysdeps (>= ${VP_VER}), amdrocm-vision-pythonpath (>= ${VP_VER}), amdrocm-decode (>= ${VP_ROCM}), amdrocm-jpeg (>= ${VP_ROCM})")
set(CPACK_DEBIAN_ROCCV_PACKAGE_DEPENDS
    "amdrocm-vision-pythonpath (>= ${VP_VER}), hip-runtime-amd (>= ${VP_ROCM})")
set(CPACK_DEBIAN_ROCPYDECODE_PACKAGE_DEPENDS
    "amdrocm-vision-pythonpath (>= ${VP_VER}), amdrocm-decode (>= ${VP_ROCM}), amdrocm-jpeg (>= ${VP_ROCM})")

# A -devel package is useless without the runtime it links against, and a -test
# package without the runtime it exercises. rocAL headers include MIVisionX
# headers, so its -devel also pulls amdrocm-mivisionx-devel.
set(CPACK_DEBIAN_MIVISIONX-DEV_PACKAGE_DEPENDS
    "amdrocm-mivisionx (>= ${VP_VER})")
set(CPACK_DEBIAN_MIVISIONX-TEST_PACKAGE_DEPENDS
    "amdrocm-mivisionx (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCAL-DEV_PACKAGE_DEPENDS
    "amdrocm-rocal (>= ${VP_VER}), amdrocm-mivisionx-devel (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCAL-TEST_PACKAGE_DEPENDS
    "amdrocm-rocal (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCCV-DEV_PACKAGE_DEPENDS
    "amdrocm-roccv (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCCV-TEST_PACKAGE_DEPENDS
    "amdrocm-roccv (>= ${VP_VER})")
set(CPACK_DEBIAN_ROCPYDECODE-TEST_PACKAGE_DEPENDS
    "amdrocm-pydecode (>= ${VP_VER})")

# ---------------------------------------------------------------------------
# RPM settings
# ---------------------------------------------------------------------------
set(CPACK_RPM_COMPONENT_INSTALL ON)
set(CPACK_RPM_PACKAGE_RELEASE   "${VISION_PACK_BUILD_ID}")
set(CPACK_RPM_PACKAGE_GROUP     "Development/Libraries")
set(CPACK_RPM_PACKAGE_LICENSE   "MIT")
set(CPACK_RPM_PACKAGE_URL       "https://github.com/ROCm/vision-pack")

set(CPACK_RPM_MIVISIONX_PACKAGE_NAME            "amdrocm-mivisionx")
set(CPACK_RPM_MIVISIONX-DEV_PACKAGE_NAME        "amdrocm-mivisionx-devel")
set(CPACK_RPM_MIVISIONX-TEST_PACKAGE_NAME       "amdrocm-mivisionx-test")
set(CPACK_RPM_ROCAL_PACKAGE_NAME                "amdrocm-rocal")
set(CPACK_RPM_ROCAL-DEV_PACKAGE_NAME            "amdrocm-rocal-devel")
set(CPACK_RPM_ROCAL-TEST_PACKAGE_NAME           "amdrocm-rocal-test")
set(CPACK_RPM_ROCCV_PACKAGE_NAME                "amdrocm-roccv")
set(CPACK_RPM_ROCCV-DEV_PACKAGE_NAME            "amdrocm-roccv-devel")
set(CPACK_RPM_ROCCV-TEST_PACKAGE_NAME           "amdrocm-roccv-test")
set(CPACK_RPM_ROCPYDECODE_PACKAGE_NAME          "amdrocm-pydecode")
set(CPACK_RPM_ROCPYDECODE-TEST_PACKAGE_NAME     "amdrocm-pydecode-test")
set(CPACK_RPM_ROCM-SYSDEPS-VISION_PACKAGE_NAME  "amdrocm-vision-sysdeps")
set(CPACK_RPM_PYTHONPATH_PACKAGE_NAME           "amdrocm-vision-pythonpath")

# Requires mirror the DEB Depends above. Without them the RPMs declared no
# dependencies at all and would install onto a host with no ROCm present.
set(CPACK_RPM_MIVISIONX_PACKAGE_REQUIRES
    "amdrocm-rpp >= ${VP_ROCM}, hip-runtime-amd >= ${VP_ROCM}")
set(CPACK_RPM_ROCAL_PACKAGE_REQUIRES
    "amdrocm-mivisionx >= ${VP_VER}, amdrocm-vision-sysdeps >= ${VP_VER}, amdrocm-vision-pythonpath >= ${VP_VER}, amdrocm-decode >= ${VP_ROCM}, amdrocm-jpeg >= ${VP_ROCM}")
set(CPACK_RPM_ROCCV_PACKAGE_REQUIRES
    "amdrocm-vision-pythonpath >= ${VP_VER}, hip-runtime-amd >= ${VP_ROCM}")
set(CPACK_RPM_ROCPYDECODE_PACKAGE_REQUIRES
    "amdrocm-vision-pythonpath >= ${VP_VER}, amdrocm-decode >= ${VP_ROCM}, amdrocm-jpeg >= ${VP_ROCM}")
set(CPACK_RPM_MIVISIONX-DEV_PACKAGE_REQUIRES
    "amdrocm-mivisionx >= ${VP_VER}")
set(CPACK_RPM_MIVISIONX-TEST_PACKAGE_REQUIRES
    "amdrocm-mivisionx >= ${VP_VER}")
set(CPACK_RPM_ROCAL-DEV_PACKAGE_REQUIRES
    "amdrocm-rocal >= ${VP_VER}, amdrocm-mivisionx-devel >= ${VP_VER}")
set(CPACK_RPM_ROCAL-TEST_PACKAGE_REQUIRES
    "amdrocm-rocal >= ${VP_VER}")
set(CPACK_RPM_ROCCV-DEV_PACKAGE_REQUIRES
    "amdrocm-roccv >= ${VP_VER}")
set(CPACK_RPM_ROCCV-TEST_PACKAGE_REQUIRES
    "amdrocm-roccv >= ${VP_VER}")
set(CPACK_RPM_ROCPYDECODE-TEST_PACKAGE_REQUIRES
    "amdrocm-pydecode >= ${VP_VER}")

# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------
set(CPACK_GENERATOR "DEB;RPM;TGZ")
set(CPACK_TGZ_COMPONENT_INSTALL ON)

include(CPack)

# ---------------------------------------------------------------------------
# Meta-packages via equivs (amdrocm-vision, amdrocm-vision-sdk, etc.)
# ---------------------------------------------------------------------------
find_program(EQUIVS_BUILD equivs-build)
if(EQUIVS_BUILD)
  # equivs-build produces one .deb from the first Package: stanza of a control
  # file, so each meta-package needs its own control file — a single multi-stanza
  # file would only ever build amdrocm-vision.
  set(_vision_meta_controls
      amdrocm-vision amdrocm-vision-sdk amdrocm-vision-tests)
  set(_meta_build_cmds "")
  foreach(_meta ${_vision_meta_controls})
    configure_file(
      "${CMAKE_CURRENT_SOURCE_DIR}/meta/${_meta}.control.in"
      "${CMAKE_CURRENT_BINARY_DIR}/meta/${_meta}.control"
      @ONLY
    )
    list(APPEND _meta_build_cmds
      COMMAND ${EQUIVS_BUILD} "${CMAKE_CURRENT_BINARY_DIR}/meta/${_meta}.control")
  endforeach()
  add_custom_target(package-meta-vision
    ${_meta_build_cmds}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/meta"
    COMMENT "Building amdrocm-vision, -sdk, -tests meta-packages"
  )
endif()
