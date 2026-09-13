include(vision_pack_bundled_dep)
include(ExternalProject)
include(CMakeDependentOption)

# ---------------------------------------------------------------------------
# Runtime RPATH strategy
#
# All bundled runtime libs install to ${CMAKE_INSTALL_PREFIX}/lib/rocm_vision/
# mirroring TheRock's rocm_sysdeps/ pattern. This directory is added to the
# RPATH of each vision library so they resolve bundled deps at runtime without
# polluting the system library path.
#
# Libs already in ROCm's rocm_sysdeps/ (zlib, bzip2, liblzma, etc.) are
# linked via -Wl,-rpath,$ORIGIN/../lib/rocm_sysdeps/lib which is already
# present in /opt/rocm — no rebundling needed.
#
# Excluded by design: ffmpeg (libavcodec/avformat/avutil/swscale) and OpenCV.
# rocAL will build with these disabled (-DBUILD_WITH_FFMPEG=OFF, etc.) so
# there is no runtime dependency on them.
# ---------------------------------------------------------------------------
set(VP_SYSDEPS_INSTALL_SUBDIR "lib/rocm_vision"
    CACHE STRING "Subdir under CMAKE_INSTALL_PREFIX for bundled runtime libs")
set(VP_BUNDLED_RPATH "$ORIGIN:$ORIGIN/../lib/rocm_vision/lib:$ORIGIN/../lib/rocm_sysdeps/lib"
    CACHE STRING "RPATH baked into vision library .so files")

# ---------------------------------------------------------------------------
# Bundling options
# ---------------------------------------------------------------------------
option(VISION_PACK_BUNDLE_PYBIND11   "Build pybind11 from bundled source"          ON)
option(VISION_PACK_BUNDLE_DLPACK     "Use bundled dlpack headers"                   ON)
option(VISION_PACK_BUNDLE_RAPIDJSON  "Use bundled RapidJSON headers"                ON)

# rocAL runtime deps — only built when rocAL is enabled
cmake_dependent_option(VISION_PACK_BUNDLE_PROTOBUF
  "Build protobuf from bundled source"        ON "VISION_PACK_ENABLE_ROCAL" OFF)
cmake_dependent_option(VISION_PACK_BUNDLE_TURBOJPEG
  "Build libjpeg-turbo from bundled source"   ON "VISION_PACK_ENABLE_ROCAL" OFF)
cmake_dependent_option(VISION_PACK_BUNDLE_LMDB
  "Build LMDB from bundled source"            ON "VISION_PACK_ENABLE_ROCAL" OFF)
cmake_dependent_option(VISION_PACK_BUNDLE_LIBSNDFILE
  "Build libsndfile from bundled source"      ON "VISION_PACK_ENABLE_ROCAL" OFF)

# Compute the bundled sysdeps install prefix
set(_vp_sysdeps_prefix "${CMAKE_BINARY_DIR}/${VP_SYSDEPS_INSTALL_SUBDIR}")

# ---------------------------------------------------------------------------
# pybind11 v3.1.0  (build-time only — compiled into .so, not shipped)
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_PYBIND11)
  set(PYBIND11_TEST OFF CACHE BOOL "" FORCE)
  add_subdirectory(pybind11)
  message(STATUS "[vision-pack] pybind11 v3.1.0 bundled (build-time only)")
else()
  find_package(pybind11 REQUIRED)
endif()

# ---------------------------------------------------------------------------
# dlpack v1.3  (build-time only — header-only, not shipped)
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_DLPACK)
  add_subdirectory(dlpack)
  vision_pack_provide_header_only(dlpack "${CMAKE_CURRENT_SOURCE_DIR}/dlpack")
else()
  find_package(dlpack REQUIRED)
endif()

# ---------------------------------------------------------------------------
# RapidJSON master  (build-time only — compiled into librocal.so, not shipped)
# Do NOT use add_subdirectory: generated RapidJSONConfig.cmake references
# parent-session targets that break ExternalProject sub-builds.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_RAPIDJSON)
  vision_pack_provide_header_only(RapidJSON "${CMAKE_CURRENT_SOURCE_DIR}/rapidjson")
else()
  find_package(RapidJSON REQUIRED)
endif()

# ---------------------------------------------------------------------------
# protobuf v3.21.12  (ships with rocAL — libprotobuf.so)
# v3.22+ requires abseil-cpp as a nested submodule; v3.21.12 is the last
# release without it and still satisfies rocAL's >=3.12.4 requirement.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_PROTOBUF)
  set(protobuf_BUILD_TESTS         OFF CACHE BOOL "" FORCE)
  set(protobuf_BUILD_EXAMPLES      OFF CACHE BOOL "" FORCE)
  set(protobuf_WITH_ZLIB           OFF CACHE BOOL "" FORCE)
  set(protobuf_MSVC_STATIC_RUNTIME OFF CACHE BOOL "" FORCE)
  # Install into the bundled sysdeps prefix so it packages with the libs
  set(protobuf_INSTALL_LIBDIR      "${_vp_sysdeps_prefix}/lib"     CACHE STRING "" FORCE)
  set(protobuf_INSTALL_INCLUDEDIR  "${_vp_sysdeps_prefix}/include" CACHE STRING "" FORCE)
  add_subdirectory(protobuf/cmake protobuf-build)
  # gcc-13 in manylinux_2_28 promotes -Wstringop-overread to an error via
  # toolset-13 spec. These are false positives in protobuf v3.21.x template
  # copy constructors. Suppress only on protobuf targets.
  foreach(_t libprotobuf libprotobuf-lite libprotoc protoc)
    if(TARGET ${_t})
      target_compile_options(${_t} PRIVATE
        -Wno-stringop-overread -Wno-error=stringop-overread)
    endif()
  endforeach()
  vision_pack_provide_package(protobuf Protobuf "third-party/protobuf-build")
  message(STATUS "[vision-pack] protobuf v3.21.12 bundled -> ${_vp_sysdeps_prefix}")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(Protobuf REQUIRED)
endif()

# ---------------------------------------------------------------------------
# libjpeg-turbo 3.2.0  (ships with rocAL — libturbojpeg.so)
# libjpeg-turbo explicitly forbids add_subdirectory(); use ExternalProject.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_TURBOJPEG)
  set(_tj_install "${_vp_sysdeps_prefix}")
  ExternalProject_Add(turbojpeg_external
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/third-party/libjpeg-turbo-build"
    INSTALL_DIR "${_tj_install}"
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DENABLE_SHARED=ON
      -DENABLE_STATIC=OFF
      -DWITH_TURBOJPEG=ON
      -DWITH_SIMD=ON
    BUILD_BYPRODUCTS
      "${_tj_install}/lib/libturbojpeg.so"
      "${_tj_install}/lib/libjpeg.so"
  )
  set(TurboJPEG_ROOT "${_tj_install}" CACHE PATH "Root of bundled libjpeg-turbo" FORCE)
  message(STATUS "[vision-pack] libjpeg-turbo 3.2.0 bundled -> ${_tj_install}")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(TurboJPEG REQUIRED)
endif()

# ---------------------------------------------------------------------------
# LMDB 1.0.1  (ships with rocAL — liblmdb.so)
# LMDB's CMakeLists is minimal — use ExternalProject for clean isolation.
# The actual library source is in libraries/liblmdb/ inside the repo.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_LMDB)
  set(_lmdb_install "${_vp_sysdeps_prefix}")
  ExternalProject_Add(lmdb_external
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/lmdb/libraries/liblmdb"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/third-party/lmdb-build"
    INSTALL_DIR "${_lmdb_install}"
    # LMDB has no CMakeLists — use its Makefile directly
    CONFIGURE_COMMAND ""
    BUILD_COMMAND
      make -C "${CMAKE_CURRENT_SOURCE_DIR}/lmdb/libraries/liblmdb"
        prefix=<INSTALL_DIR>
        "CFLAGS=-O2 -fPIC"
    INSTALL_COMMAND
      make -C "${CMAKE_CURRENT_SOURCE_DIR}/lmdb/libraries/liblmdb"
        prefix=<INSTALL_DIR>
        install
    BUILD_BYPRODUCTS
      "${_lmdb_install}/lib/liblmdb.so"
  )
  set(LMDB_ROOT "${_lmdb_install}" CACHE PATH "Root of bundled LMDB" FORCE)
  message(STATUS "[vision-pack] LMDB 1.0.1 bundled -> ${_lmdb_install}")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(LMDB QUIET)
  if(NOT LMDB_FOUND)
    find_library(LMDB_LIBRARIES NAMES lmdb)
    find_path(LMDB_INCLUDE_DIRS NAMES lmdb.h)
    if(LMDB_LIBRARIES AND LMDB_INCLUDE_DIRS)
      set(LMDB_FOUND TRUE)
    endif()
  endif()
endif()

# ---------------------------------------------------------------------------
# libsndfile 1.2.2  (ships with rocAL — libsndfile.so)
# Required for rocAL audio augmentation support.
# Built without external format encoders (mp3, vorbis etc.) — those are
# optional and pull in heavy deps we want to avoid.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_LIBSNDFILE)
  set(_sndfile_install "${_vp_sysdeps_prefix}")
  ExternalProject_Add(libsndfile_external
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/libsndfile"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/third-party/libsndfile-build"
    INSTALL_DIR "${_sndfile_install}"
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DBUILD_SHARED_LIBS=ON
      -DBUILD_PROGRAMS=OFF
      -DBUILD_EXAMPLES=OFF
      -DBUILD_TESTING=OFF
      # Disable optional heavy encoders — keep libsndfile self-contained
      -DENABLE_EXTERNAL_LIBS=OFF
      -DENABLE_MPEG=OFF
    BUILD_BYPRODUCTS
      "${_sndfile_install}/lib/libsndfile.so"
  )
  set(SndFile_ROOT "${_sndfile_install}" CACHE PATH "Root of bundled libsndfile" FORCE)
  message(STATUS "[vision-pack] libsndfile 1.2.2 bundled -> ${_sndfile_install}")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(SndFile QUIET)
endif()

# ---------------------------------------------------------------------------
# Expose bundled sysdeps prefix via a cache variable so the top-level
# CMakeLists and vision_pack_subproject.cmake can pass it to rocAL's
# configure step.
# ---------------------------------------------------------------------------
set(VP_BUNDLED_DEPS_PREFIX "${_vp_sysdeps_prefix}"
    CACHE PATH "Install prefix for all bundled runtime deps" FORCE)
