# CPack configuration for amdrocm-vision packages.
#
# Produces DEB + RPM + TGZ packages following the amdrocm-* naming scheme
# from https://github.com/ROCm/MIVisionX/issues/1756.
#
# Package hierarchy:
#
#   amdrocm-vision          runtime meta  (all runtime component libs)
#   amdrocm-vision-sdk      dev meta      (runtime + all dev headers/cmake)
#   amdrocm-vision-tests    test meta     (sdk + all test suites)
#
#   Component packages:
#     amdrocm-mivisionx / amdrocm-mivisionx-devel / amdrocm-mivisionx-test
#     amdrocm-rocal      / amdrocm-rocal-devel      / amdrocm-rocal-test
#     amdrocm-roccv      / amdrocm-roccv-devel       / amdrocm-roccv-test
#     amdrocm-rocpydecode                            / amdrocm-rocpydecode-test
#
# Usage (from build dir after cmake --install --prefix staging/):
#   cmake --build . --target package

cmake_minimum_required(VERSION 3.21)
project(vision-pack-cpack NONE)

# ---------------------------------------------------------------------------
# Version from parent project or environment
# ---------------------------------------------------------------------------
if(NOT DEFINED VISION_PACK_VERSION)
  set(VISION_PACK_VERSION "0.1.0" CACHE STRING "Package version")
endif()
if(NOT DEFINED VISION_PACK_ROCM_VERSION)
  set(VISION_PACK_ROCM_VERSION "10.1.0" CACHE STRING "ROCm SDK version this was built against")
endif()
if(NOT DEFINED VISION_PACK_BUILD_ID)
  set(VISION_PACK_BUILD_ID "0" CACHE STRING "CI build ID / run number")
endif()

set(VP_VER "${VISION_PACK_VERSION}")
set(VP_ROCM "${VISION_PACK_ROCM_VERSION}")

# ---------------------------------------------------------------------------
# Staging directory — populated by cmake --install of each subproject
# ---------------------------------------------------------------------------
if(NOT DEFINED VISION_PACK_STAGING_DIR)
  set(VISION_PACK_STAGING_DIR "${CMAKE_BINARY_DIR}/staging" CACHE PATH
      "Directory containing the installed vision libraries")
endif()

# ---------------------------------------------------------------------------
# CPack global settings
# ---------------------------------------------------------------------------
set(CPACK_PACKAGE_NAME              "amdrocm-vision")
set(CPACK_PACKAGE_VERSION           "${VP_VER}")
set(CPACK_PACKAGE_VENDOR            "Advanced Micro Devices, Inc.")
set(CPACK_PACKAGE_CONTACT           "rocm-support@amd.com")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY
    "AMD ROCm Computer Vision extension pack (MIVisionX, rocAL, rocCV, rocPyDecode)")
set(CPACK_RESOURCE_FILE_LICENSE     "${CMAKE_CURRENT_SOURCE_DIR}/../LICENSE")

set(CPACK_PACKAGING_INSTALL_PREFIX  "/opt/rocm")
set(CPACK_INSTALL_CMAKE_PROJECTS    "")   # We install files directly below

set(CPACK_COMPONENTS_ALL
    mivisionx mivisionx-dev mivisionx-test
    rocal      rocal-dev     rocal-test
    roccv      roccv-dev     roccv-test
    rocpydecode               rocpydecode-test
)

set(CPACK_COMPONENT_GROUPS_ALL  vision vision-sdk vision-tests)

# ---------------------------------------------------------------------------
# Component → Group mapping
# ---------------------------------------------------------------------------
# Runtime group
foreach(_c mivisionx rocal roccv rocpydecode)
  set("CPACK_COMPONENT_${_c}_GROUP" "vision")
  string(TOUPPER "${_c}" _u)
  set("CPACK_COMPONENT_${_u}_GROUP" "vision")
endforeach()

# Dev group (includes runtime)
foreach(_c mivisionx-dev rocal-dev roccv-dev)
  string(TOUPPER "${_c}" _u)
  set("CPACK_COMPONENT_${_u}_GROUP" "vision-sdk")
  set("CPACK_COMPONENT_${_u}_DEPENDS" "${_c}")
endforeach()

# Test group (includes dev)
foreach(_c mivisionx-test rocal-test roccv-test rocpydecode-test)
  string(TOUPPER "${_c}" _u)
  set("CPACK_COMPONENT_${_u}_GROUP" "vision-tests")
  string(REPLACE "-test" "" _base "${_c}")
  set("CPACK_COMPONENT_${_u}_DEPENDS" "${_base}")
endforeach()

# ---------------------------------------------------------------------------
# Component display names and descriptions
# ---------------------------------------------------------------------------
set(CPACK_COMPONENT_MIVISIONX_DISPLAY_NAME     "AMD MIVisionX runtime")
set(CPACK_COMPONENT_MIVISIONX_DESCRIPTION
    "OpenVX engine (libopenvx, libvxu) and RPP extension (libvx_rpp). Runtime libraries.")
set(CPACK_COMPONENT_MIVISIONX_DEV_DISPLAY_NAME "AMD MIVisionX development files")
set(CPACK_COMPONENT_MIVISIONX_DEV_DESCRIPTION
    "Headers, cmake config, and samples for MIVisionX.")

set(CPACK_COMPONENT_ROCAL_DISPLAY_NAME         "AMD rocAL runtime")
set(CPACK_COMPONENT_ROCAL_DESCRIPTION
    "ROCm Augmentation Library (librocal) and Python bindings.")
set(CPACK_COMPONENT_ROCAL_DEV_DISPLAY_NAME     "AMD rocAL development files")
set(CPACK_COMPONENT_ROCAL_DEV_DESCRIPTION
    "Headers and cmake config for rocAL.")

set(CPACK_COMPONENT_ROCCV_DISPLAY_NAME         "AMD rocCV runtime")
set(CPACK_COMPONENT_ROCCV_DESCRIPTION
    "ROCm GPU-accelerated image processing library (libroccv) and Python bindings.")
set(CPACK_COMPONENT_ROCCV_DEV_DISPLAY_NAME     "AMD rocCV development files")
set(CPACK_COMPONENT_ROCCV_DEV_DESCRIPTION
    "Headers and cmake config for rocCV.")

set(CPACK_COMPONENT_ROCPYDECODE_DISPLAY_NAME   "AMD rocPyDecode runtime")
set(CPACK_COMPONENT_ROCPYDECODE_DESCRIPTION
    "Python bindings for rocDecode video and JPEG hardware decode.")

# ---------------------------------------------------------------------------
# Install rules — pull files from staging dir into CPack components
# ---------------------------------------------------------------------------

# MIVisionX runtime: shared libs + runvx
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/"
    DESTINATION lib
    COMPONENT mivisionx
    FILES_MATCHING
      PATTERN "libopenvx.so*"
      PATTERN "libvxu.so*"
      PATTERN "libvx_rpp.so*"
)
install(PROGRAMS "${VISION_PACK_STAGING_DIR}/bin/runvx"
    DESTINATION bin
    COMPONENT mivisionx
    OPTIONAL
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/mivisionx/LICENSE.txt"
    DESTINATION share/doc/amdrocm-mivisionx
    COMPONENT mivisionx
    OPTIONAL
)

# MIVisionX dev: headers + cmake config + samples
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/include/mivisionx"
    DESTINATION include
    COMPONENT mivisionx-dev
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/mivisionx"
    DESTINATION share
    COMPONENT mivisionx-dev
)

# MIVisionX tests
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/mivisionx/test"
    DESTINATION share/amdrocm-mivisionx
    COMPONENT mivisionx-test
    OPTIONAL
)

# rocAL runtime: librocal + python binding
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/"
    DESTINATION lib
    COMPONENT rocal
    FILES_MATCHING
      PATTERN "librocal.so*"
      PATTERN "rocal_pybind*.so"
      PATTERN "amd/*"
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/rocal/LICENSE.txt"
    DESTINATION share/doc/amdrocm-rocal
    COMPONENT rocal
    OPTIONAL
)

# rocAL dev: headers
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/include/rocal"
    DESTINATION include
    COMPONENT rocal-dev
)

# rocAL tests
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/rocal/test"
    DESTINATION share/amdrocm-rocal
    COMPONENT rocal-test
    OPTIONAL
)

# rocCV runtime: libroccv + python binding + type stubs
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/"
    DESTINATION lib
    COMPONENT roccv
    FILES_MATCHING
      PATTERN "libroccv.so*"
      PATTERN "rocpycv*.so"
      PATTERN "rocpycv.pyi"
)
install(FILES "${VISION_PACK_STAGING_DIR}/share/doc/roccv/LICENSE.txt"
    DESTINATION share/doc/amdrocm-roccv
    COMPONENT roccv
    OPTIONAL
)

# rocCV dev: headers + cmake config
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/include/roccv"
    DESTINATION include
    COMPONENT roccv-dev
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/cmake/roccv"
    DESTINATION lib/cmake
    COMPONENT roccv-dev
    OPTIONAL
)

# rocCV tests
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/roccv/test"
    DESTINATION share/amdrocm-roccv
    COMPONENT roccv-test
    OPTIONAL
)

# rocPyDecode runtime: Python extension modules + packages
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/lib/"
    DESTINATION lib
    COMPONENT rocpydecode
    FILES_MATCHING
      PATTERN "rocpydecode*.so"
      PATTERN "rocpyjpegdecode*.so"
      PATTERN "pyRocVideoDecode/*"
      PATTERN "pyRocJpegDecode/*"
)

# rocPyDecode tests
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/rocpydecode/tests"
    DESTINATION share/amdrocm-rocpydecode
    COMPONENT rocpydecode-test
    OPTIONAL
)
install(DIRECTORY "${VISION_PACK_STAGING_DIR}/share/rocpyjpegdecode/tests"
    DESTINATION share/amdrocm-rocpydecode
    COMPONENT rocpydecode-test
    OPTIONAL
)

# ---------------------------------------------------------------------------
# DEB-specific settings
# ---------------------------------------------------------------------------
set(CPACK_DEB_COMPONENT_INSTALL ON)
set(CPACK_DEBIAN_PACKAGE_RELEASE "${VISION_PACK_BUILD_ID}")
set(CPACK_DEBIAN_PACKAGE_SECTION "devel")
set(CPACK_DEBIAN_PACKAGE_PRIORITY "optional")
set(CPACK_DEBIAN_PACKAGE_MAINTAINER "ROCm Engineering <rocm-support@amd.com>")
set(CPACK_DEBIAN_PACKAGE_HOMEPAGE  "https://github.com/ROCm/vision-pack")

# Per-component DEB package names → amdrocm-* scheme
set(CPACK_DEBIAN_MIVISIONX_PACKAGE_NAME         "amdrocm-mivisionx")
set(CPACK_DEBIAN_MIVISIONX-DEV_PACKAGE_NAME     "amdrocm-mivisionx-devel")
set(CPACK_DEBIAN_MIVISIONX-TEST_PACKAGE_NAME    "amdrocm-mivisionx-test")
set(CPACK_DEBIAN_ROCAL_PACKAGE_NAME             "amdrocm-rocal")
set(CPACK_DEBIAN_ROCAL-DEV_PACKAGE_NAME         "amdrocm-rocal-devel")
set(CPACK_DEBIAN_ROCAL-TEST_PACKAGE_NAME        "amdrocm-rocal-test")
set(CPACK_DEBIAN_ROCCV_PACKAGE_NAME             "amdrocm-roccv")
set(CPACK_DEBIAN_ROCCV-DEV_PACKAGE_NAME         "amdrocm-roccv-devel")
set(CPACK_DEBIAN_ROCCV-TEST_PACKAGE_NAME        "amdrocm-roccv-test")
set(CPACK_DEBIAN_ROCPYDECODE_PACKAGE_NAME       "amdrocm-rocpydecode")
set(CPACK_DEBIAN_ROCPYDECODE-TEST_PACKAGE_NAME  "amdrocm-rocpydecode-test")

# Runtime deps for each package
set(CPACK_DEBIAN_MIVISIONX_PACKAGE_DEPENDS
    "amdrocm-rpp (>= ${VP_ROCM}), hip-runtime-amd (>= ${VP_ROCM})")
set(CPACK_DEBIAN_ROCAL_PACKAGE_DEPENDS
    "amdrocm-mivisionx (>= ${VP_VER}), amdrocm-rpp (>= ${VP_ROCM}), libturbojpeg0, liblmdb0")
set(CPACK_DEBIAN_ROCCV_PACKAGE_DEPENDS
    "hip-runtime-amd (>= ${VP_ROCM})")
set(CPACK_DEBIAN_ROCPYDECODE_PACKAGE_DEPENDS
    "amdrocm-decode (>= ${VP_ROCM}), amdrocm-jpeg (>= ${VP_ROCM})")

# ---------------------------------------------------------------------------
# RPM-specific settings
# ---------------------------------------------------------------------------
set(CPACK_RPM_COMPONENT_INSTALL ON)
set(CPACK_RPM_PACKAGE_RELEASE   "${VISION_PACK_BUILD_ID}")
set(CPACK_RPM_PACKAGE_GROUP     "Development/Libraries")
set(CPACK_RPM_PACKAGE_LICENSE   "MIT")
set(CPACK_RPM_PACKAGE_URL       "https://github.com/ROCm/vision-pack")

set(CPACK_RPM_MIVISIONX_PACKAGE_NAME         "amdrocm-mivisionx")
set(CPACK_RPM_MIVISIONX-DEV_PACKAGE_NAME     "amdrocm-mivisionx-devel")
set(CPACK_RPM_MIVISIONX-TEST_PACKAGE_NAME    "amdrocm-mivisionx-test")
set(CPACK_RPM_ROCAL_PACKAGE_NAME             "amdrocm-rocal")
set(CPACK_RPM_ROCAL-DEV_PACKAGE_NAME         "amdrocm-rocal-devel")
set(CPACK_RPM_ROCAL-TEST_PACKAGE_NAME        "amdrocm-rocal-test")
set(CPACK_RPM_ROCCV_PACKAGE_NAME             "amdrocm-roccv")
set(CPACK_RPM_ROCCV-DEV_PACKAGE_NAME         "amdrocm-roccv-devel")
set(CPACK_RPM_ROCCV-TEST_PACKAGE_NAME        "amdrocm-roccv-test")
set(CPACK_RPM_ROCPYDECODE_PACKAGE_NAME       "amdrocm-rocpydecode")
set(CPACK_RPM_ROCPYDECODE-TEST_PACKAGE_NAME  "amdrocm-rocpydecode-test")

# ---------------------------------------------------------------------------
# TGZ (tarball) settings
# ---------------------------------------------------------------------------
set(CPACK_TGZ_COMPONENT_INSTALL ON)

# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------
set(CPACK_GENERATOR "DEB;RPM;TGZ")

include(CPack)

# ---------------------------------------------------------------------------
# Meta-package generation (pure dependency packages, no files)
# Written as post-install scripts that create empty meta .deb/.rpm packages.
# For simplicity we generate them via a custom target.
# ---------------------------------------------------------------------------
find_program(EQUIVS_BUILD equivs-build)
if(EQUIVS_BUILD)
  # amdrocm-vision meta (runtime)
  configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/meta/amdrocm-vision.control.in"
    "${CMAKE_CURRENT_BINARY_DIR}/meta/amdrocm-vision.control"
    @ONLY
  )
  add_custom_target(package-meta-vision
    COMMAND ${EQUIVS_BUILD} "${CMAKE_CURRENT_BINARY_DIR}/meta/amdrocm-vision.control"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/meta"
    COMMENT "Building amdrocm-vision meta-package"
  )
endif()
