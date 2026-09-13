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
# ROCm SDK (pre-built Quartz nightly or stable release)
# ---------------------------------------------------------------------------
if(NOT DEFINED ROCM_PATH)
  set(ROCM_PATH "/opt/rocm" CACHE PATH "Path to the ROCm SDK installation")
endif()
message(STATUS "[vision-pack] Using ROCm SDK at: ${ROCM_PATH}")

# ---------------------------------------------------------------------------
# Component enable flags
# ---------------------------------------------------------------------------
option(VISION_PACK_ENABLE_MIVISIONX  "Build MIVisionX"   ON)
option(VISION_PACK_ENABLE_ROCAL      "Build rocAL"        ON)
option(VISION_PACK_ENABLE_ROCCV      "Build rocCV"        ON)
option(VISION_PACK_ENABLE_ROCPYDECODE "Build rocPyDecode" ON)

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
# Third-party bundled dependencies
# Only build compiled deps (protobuf, turbojpeg) when rocAL is enabled.
# Header-only deps (pybind11, dlpack, rapidjson) are always available.
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
      "-DCMAKE_INSTALL_RPATH=${VP_BUNDLED_RPATH}"
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
  )
endif()

# rocCV — no inter-library deps, only needs ROCm SDK
if(VISION_PACK_ENABLE_ROCCV)
  vision_pack_subproject_declare(rocCV
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rocCV"
    CMAKE_ARGS
      -DBUILD_PYPACKAGE=ON
      "-DCMAKE_INSTALL_RPATH=${VP_BUNDLED_RPATH}"
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
  )
endif()

# rocPyDecode — depends only on rocDecode/rocJPEG already in the SDK
# rocpydecode hardcodes ${ROCM_PATH}/share/rocdecode/utils to find utility
# sources. If they are not at ${ROCM_PATH}/share/rocdecode/utils, set
# ROCPYDECODE_ROCM_PATH to the prefix that contains them.
if(NOT DEFINED ROCPYDECODE_ROCM_PATH)
  if(EXISTS "${ROCM_PATH}/share/rocdecode/utils")
    set(ROCPYDECODE_ROCM_PATH "${ROCM_PATH}")
  elseif(EXISTS "${ROCM_PATH}/core-10.1/share/rocdecode/utils")
    set(ROCPYDECODE_ROCM_PATH "${ROCM_PATH}/core-10.1")
  else()
    set(ROCPYDECODE_ROCM_PATH "${ROCM_PATH}")
  endif()
endif()
if(VISION_PACK_ENABLE_ROCPYDECODE)
  vision_pack_subproject_declare(rocpydecode
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rocpydecode"
    CMAKE_ARGS "-DROCM_PATH=${ROCPYDECODE_ROCM_PATH}"
  )
endif()

# rocAL — depends on mivisionx stage + all bundled runtime deps
# ffmpeg and opencv are explicitly disabled — they carry heavy transitive deps
# and are not needed for the core augmentation functionality.
if(VISION_PACK_ENABLE_ROCAL)
  set(_rocal_deps "")
  set(_rocal_extra_deps "")
  # Bundled sysdeps prefix (set by third-party/CMakeLists.txt after add_subdirectory)
  set(_bdeps "${VP_BUNDLED_DEPS_PREFIX}")

  set(_rocal_cmake_args
    -DBACKEND=HIP
    -DGPU_SUPPORT=ON
    -DBUILD_PYPACKAGE=ON
    # Disable ffmpeg — heavy transitive deps, excluded by design
    -DBUILD_WITH_FFMPEG=OFF
    # Disable OpenCV — excluded by design
    -DBUILD_WITH_OPENCV=OFF
    # Bake RPATH so bundled libs are found at runtime without LD_LIBRARY_PATH
    "-DCMAKE_INSTALL_RPATH=${VP_BUNDLED_RPATH}"
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
    # RapidJSON finder injected via CMAKE_MODULE_PATH (vision_pack_subproject)
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
    list(APPEND _rocal_cmake_args
      "-DTURBO_JPEG_PATH=${_bdeps}"
    )
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
      "-DLMDB_INCLUDE_DIR=${_bdeps}/include"
      "-DLMDB_LIBRARY=${_bdeps}/lib/liblmdb.so"
    )
  endif()

  if(VISION_PACK_BUNDLE_LIBSNDFILE)
    list(APPEND _rocal_extra_deps libsndfile_external)
    list(APPEND _rocal_cmake_args
      "-DSndFile_ROOT=${_bdeps}"
    )
  endif()

  vision_pack_subproject_declare(rocal
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/rocal"
    DEPS        ${_rocal_deps}
    EXTRA_DEPS  ${_rocal_extra_deps}
    CMAKE_ARGS  ${_rocal_cmake_args}
  )
endif()

# Wire up all declared subprojects
vision_pack_subproject_activate()
