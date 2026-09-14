cmake_minimum_required(VERSION 3.21)

project(vision-pack
  VERSION 0.1.0
  LANGUAGES C CXX
  DESCRIPTION "AMD ROCm Computer Vision package aggregator")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

# ---------------------------------------------------------------------------
# ROCm SDK — pre-built Quartz nightly or stable release.
# All vision libraries and their bundled deps install INTO this prefix,
# mirroring the exact layout of /opt/rocm (same as any other ROCm component).
# ---------------------------------------------------------------------------
if(NOT DEFINED ROCM_PATH)
  set(ROCM_PATH "/opt/rocm" CACHE PATH "Path to the ROCm SDK installation")
endif()
# CMAKE_INSTALL_PREFIX defaults to ROCM_PATH so `cmake --install` drops
# everything directly into the ROCm tree — no new top-level dirs.
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${ROCM_PATH}" CACHE PATH "" FORCE)
endif()
message(STATUS "[vision-pack] Using ROCm SDK at: ${ROCM_PATH}")
message(STATUS "[vision-pack] Install prefix:    ${CMAKE_INSTALL_PREFIX}")

# ---------------------------------------------------------------------------
# RPATH strategy — identical to how ROCm libs find rocm_sysdeps at runtime.
# $ORIGIN/../lib/rocm_sysdeps/lib  finds our bundled deps AND existing ROCm
#   sysdeps (zlib, bzip2, liblzma etc.) — no new directory, already exists.
# $ORIGIN                          finds sibling libs (libopenvx → libvx_rpp).
# ---------------------------------------------------------------------------
set(VP_INSTALL_RPATH
    "$ORIGIN:$ORIGIN/../lib/rocm_sysdeps/lib"
    CACHE STRING "RPATH baked into all vision .so files")

# ---------------------------------------------------------------------------
# Component enable flags
# ---------------------------------------------------------------------------
option(VISION_PACK_ENABLE_MIVISIONX   "Build MIVisionX"   ON)
option(VISION_PACK_ENABLE_ROCAL       "Build rocAL"        ON)
option(VISION_PACK_ENABLE_ROCCV       "Build rocCV"        ON)
option(VISION_PACK_ENABLE_ROCPYDECODE "Build rocPyDecode"  ON)

# ---------------------------------------------------------------------------
# Build parallelism for sub-builds
# ---------------------------------------------------------------------------
include(ProcessorCount)
ProcessorCount(VP_NPROC)
if(NOT VP_NPROC OR VP_NPROC EQUAL 0)
  set(VP_NPROC 8)
endif()
set(VP_BUILD_PARALLEL_LEVEL "${VP_NPROC}" CACHE STRING
  "Parallel jobs for each subproject build")

# ---------------------------------------------------------------------------
# Third-party bundled dependencies.
# Compiled runtime deps (turbojpeg, protobuf, lmdb, libsndfile) install to
# lib/rocm_sysdeps/lib/ — the same dir ROCm uses for zlib, bzip2, etc.
# Header-only deps (pybind11, dlpack, rapidjson) are build-time only.
# ffmpeg and OpenCV are excluded by design (heavy transitive deps).
# ---------------------------------------------------------------------------
add_subdirectory(third-party)

# ---------------------------------------------------------------------------
# Subproject orchestration
# ---------------------------------------------------------------------------
include(vision_pack_subproject)

# mivisionx — no inter-library deps, only needs ROCm SDK
if(VISION_PACK_ENABLE_MIVISIONX)
  vision_pack_subproject_declare(mivisionx
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/mivisionx"
    CMAKE_ARGS
      -DBACKEND=HIP
      -DGPU_SUPPORT=ON
      # Install into ROCM_PATH (same as any ROCm lib):
      #   lib/libopenvx.so, include/mivisionx/, lib/cmake/mivisionx/, etc.
      "-DCMAKE_INSTALL_RPATH=${VP_INSTALL_RPATH}"
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
  )
endif()

# rocCV — no inter-library deps, only needs ROCm SDK
if(VISION_PACK_ENABLE_ROCCV)
  # In manylinux the Python dev headers are under /opt/python/cp312-cp312.
  # find_package(Python3 Development) needs a hint to find them.
  # Python3_ROOT_DIR tells cmake where to look.
  find_package(Python3 QUIET COMPONENTS Interpreter Development)
  set(_roccv_python_args "")
  if(Python3_EXECUTABLE)
    list(APPEND _roccv_python_args
      "-DPython3_EXECUTABLE=${Python3_EXECUTABLE}"
      "-DPython3_INCLUDE_DIRS=${Python3_INCLUDE_DIRS}"
      "-DPython3_LIBRARIES=${Python3_LIBRARIES}"
    )
  endif()
  vision_pack_subproject_declare(rocCV
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rocCV"
    CMAKE_ARGS
      -DBUILD_PYPACKAGE=ON
      "-DCMAKE_INSTALL_RPATH=${VP_INSTALL_RPATH}"
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
      ${_roccv_python_args}
  )
endif()

# rocPyDecode — depends only on rocDecode/rocJPEG already in the SDK.
# rocpydecode hardcodes ${ROCM_PATH}/share/rocdecode/utils for utility sources.
# Detect whether they live at the root or in a core-X.Y overlay.
if(NOT DEFINED ROCPYDECODE_ROCM_PATH)
  # rocpydecode hardcodes ${ROCM_PATH}/share/rocdecode/utils.
  # When using a Quartz nightly tarball (ROCM_PATH=/opt/rocm-nightly) the
  # rocdecode utils come from a separate deb package and land at
  # /opt/rocm/core-X.Y/share/rocdecode/utils — a different root.
  # Search both ROCM_PATH and /opt/rocm for a core-X.Y overlay.
  if(EXISTS "${ROCM_PATH}/share/rocdecode/utils")
    set(ROCPYDECODE_ROCM_PATH "${ROCM_PATH}")
  else()
    # Search ROCM_PATH first, then the canonical /opt/rocm for overlays
    set(_rocm_search_roots "${ROCM_PATH}" "/opt/rocm")
    foreach(_root ${_rocm_search_roots})
      file(GLOB _rocm_cores "${_root}/core-*/share/rocdecode/utils")
      if(_rocm_cores)
        list(GET _rocm_cores 0 _core_utils)
        # Walk up 3 levels: utils -> rocdecode -> share -> core-X.Y root
        get_filename_component(_core_root "${_core_utils}" DIRECTORY)
        get_filename_component(_core_root "${_core_root}" DIRECTORY)
        get_filename_component(_core_root "${_core_root}" DIRECTORY)
        set(ROCPYDECODE_ROCM_PATH "${_core_root}")
        break()
      endif()
    endforeach()
    if(NOT DEFINED ROCPYDECODE_ROCM_PATH)
      set(ROCPYDECODE_ROCM_PATH "${ROCM_PATH}")
      message(WARNING "[vision-pack] rocdecode utils not found — rocPyDecode "
        "video decode may fail. Install amdrocm-decode-test.")
    endif()
  endif()
endif()
message(STATUS "[vision-pack] rocPyDecode ROCM_PATH: ${ROCPYDECODE_ROCM_PATH}")
if(VISION_PACK_ENABLE_ROCPYDECODE)
  vision_pack_subproject_declare(rocpydecode
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rocpydecode"
    CMAKE_ARGS "-DROCM_PATH=${ROCPYDECODE_ROCM_PATH}"
  )
endif()

# rocAL — depends on mivisionx stage + bundled runtime deps.
# ffmpeg and OpenCV disabled — excluded by design.
if(VISION_PACK_ENABLE_ROCAL)
  set(_rocal_deps "")
  set(_rocal_extra_deps "")
  # Bundled sysdeps staging dir (set by third-party/CMakeLists.txt)
  set(_bstage "${VP_BUNDLED_DEPS_STAGE}")

  set(_rocal_cmake_args
    -DBACKEND=HIP
    -DGPU_SUPPORT=ON
    -DBUILD_PYPACKAGE=ON
    -DBUILD_WITH_FFMPEG=OFF
    -DBUILD_WITH_OPENCV=OFF
    "-DCMAKE_INSTALL_RPATH=${VP_INSTALL_RPATH}"
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
  )

  if(VISION_PACK_ENABLE_MIVISIONX)
    list(APPEND _rocal_deps mivisionx)
    list(APPEND _rocal_cmake_args
      "-DOPENVX_LIBRARIES=${CMAKE_BINARY_DIR}/_subprojects/mivisionx/stage/lib/libopenvx.so"
      "-DVXRPP_LIBRARIES=${CMAKE_BINARY_DIR}/_subprojects/mivisionx/stage/lib/libvx_rpp.so"
      "-DMIVisionX_INCLUDE_DIRS=${CMAKE_BINARY_DIR}/_subprojects/mivisionx/stage/include/mivisionx"
      "-DMIVisionX_FOUND=TRUE"
    )
  endif()

  if(VISION_PACK_BUNDLE_TURBOJPEG)
    list(APPEND _rocal_extra_deps turbojpeg_external)
    list(APPEND _rocal_cmake_args "-DTURBO_JPEG_PATH=${_bstage}")
  endif()

  if(VISION_PACK_BUNDLE_PROTOBUF)
    list(APPEND _rocal_extra_deps libprotobuf)
    list(APPEND _rocal_cmake_args
      "-DProtobuf_ROOT=${CMAKE_BINARY_DIR}/third-party/protobuf-build"
      "-DCMAKE_POLICY_DEFAULT_CMP0074=NEW"
    )
  endif()

  if(VISION_PACK_BUNDLE_LMDB)
    list(APPEND _rocal_extra_deps lmdb_external)
    list(APPEND _rocal_cmake_args
      "-DLMDB_INCLUDE_DIR=${_bstage}/include"
      "-DLMDB_LIBRARY=${_bstage}/lib/liblmdb.so"
    )
  endif()

  if(VISION_PACK_BUNDLE_LIBSNDFILE)
    list(APPEND _rocal_extra_deps libsndfile_external)
    list(APPEND _rocal_cmake_args "-DSndFile_ROOT=${_bstage}")
  endif()

  vision_pack_subproject_declare(rocal
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rocal"
    DEPS       ${_rocal_deps}
    EXTRA_DEPS ${_rocal_extra_deps}
    CMAKE_ARGS ${_rocal_cmake_args}
  )
endif()

# Wire up all declared subprojects
vision_pack_subproject_activate()
