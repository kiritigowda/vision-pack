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

# Note: the aggregator never compiles the libraries' test suites. Each library
# installs its test *sources* + data as a `test` component (→ share/<lib>/test),
# which the -test packages ship. Tests are built on the target device against
# the installed runtime — the CI test stage mirrors that. So no -DTESTS=ON here.

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
  vision_pack_subproject_declare(rocCV
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rocCV"
    CMAKE_ARGS
      -DBUILD_PYPACKAGE=ON
      "-DCMAKE_INSTALL_RPATH=${VP_INSTALL_RPATH}"
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
      # Forward Python3_ROOT_DIR if set (e.g. to /opt/python-shared/cp312-cp312
      # in manylinux where the static /opt/python build lacks libpython.so)
      $<$<BOOL:${Python3_ROOT_DIR}>:-DPython3_ROOT_DIR=${Python3_ROOT_DIR}>
  )
endif()

# rocPyDecode — depends only on rocDecode/rocJPEG already in the SDK.
# rocpydecode hardcodes ${ROCM_PATH}/share/rocdecode/utils for utility sources,
# which the dcgpu-tests SDK tarball provides directly under ROCM_PATH.
if(VISION_PACK_ENABLE_ROCPYDECODE)
  set(_rocpydecode_cmake_args "-DROCM_PATH=${ROCM_PATH}")
  # rocpydecode calls find_package(Python3 ... Development) which needs
  # libpython3.x.so. Forward Python3_ROOT_DIR if set (e.g. to
  # /opt/python-shared in manylinux where the default Python is static).
  # Upstream fix tracked: https://github.com/ROCm/rocPyDecode/issues/290
  if(Python3_ROOT_DIR)
    list(APPEND _rocpydecode_cmake_args "-DPython3_ROOT_DIR=${Python3_ROOT_DIR}")
  endif()
  vision_pack_subproject_declare(rocpydecode
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/rocpydecode"
    CMAKE_ARGS ${_rocpydecode_cmake_args}
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
    list(APPEND _rocal_extra_deps libprotobuf protoc)
    # rocAL calls find_package(Protobuf QUIET) with no CONFIG keyword, so the
    # builtin FindProtobuf.cmake (MODULE mode) runs. Config-package hints
    # (Protobuf_ROOT, protobuf_MODULE_COMPATIBLE) are inert in module mode, so
    # seed the exact result cache variables FindProtobuf reads. Pre-set as
    # cache entries, its find_library/find_path/find_program calls are no-ops
    # and it resolves the bundled build tree — setting Protobuf_FOUND and the
    # PROTOBUF_LIBRARIES/INCLUDE_DIRS that rocAL's dep check and codegen need.
    set(_pb_src "${CMAKE_CURRENT_SOURCE_DIR}/third-party/protobuf/src")
    set(_pb_build "${CMAKE_BINARY_DIR}/third-party/protobuf-build")
    # Point at the SHARED protobuf (built with protobuf_BUILD_SHARED_LIBS=ON in
    # third-party/) so librocal.so gets libprotobuf.so as a real DT_NEEDED and
    # uses the copy shipped in rocm_sysdeps/, not a private static archive (#10).
    list(APPEND _rocal_cmake_args
      "-DProtobuf_INCLUDE_DIR=${_pb_src}"
      "-DProtobuf_LIBRARY_RELEASE=${_pb_build}/libprotobuf.so"
      "-DProtobuf_LITE_LIBRARY_RELEASE=${_pb_build}/libprotobuf-lite.so"
      "-DProtobuf_PROTOC_LIBRARY_RELEASE=${_pb_build}/libprotoc.so"
      "-DProtobuf_PROTOC_EXECUTABLE=${_pb_build}/protoc"
    )
  endif()

  if(VISION_PACK_BUNDLE_LMDB)
    list(APPEND _rocal_extra_deps lmdb_external)
    list(APPEND _rocal_cmake_args
      # rocAL's FindLMDB.cmake searches via ${LMDB_DIR}/include and ${LMDB_DIR}/lib
      "-DLMDB_DIR=${_bstage}"
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
