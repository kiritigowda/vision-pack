include(vision_pack_bundled_dep)
include(ExternalProject)
include(CMakeDependentOption)

# ---------------------------------------------------------------------------
# Bundling options — set OFF to use system-installed packages instead.
# CI always builds with all ON. Distro packaging builds with all OFF.
#
# Compiled deps (protobuf, turbojpeg) are only needed when rocAL is enabled.
# Header-only deps (pybind11, dlpack, rapidjson) are always available.
# ---------------------------------------------------------------------------
option(VISION_PACK_BUNDLE_PYBIND11   "Build pybind11 from bundled source"     ON)
option(VISION_PACK_BUNDLE_DLPACK     "Use bundled dlpack headers"              ON)
option(VISION_PACK_BUNDLE_RAPIDJSON  "Use bundled RapidJSON headers"           ON)

# Compiled deps only make sense when rocAL is enabled
cmake_dependent_option(VISION_PACK_BUNDLE_PROTOBUF
  "Build protobuf from bundled source" ON
  "VISION_PACK_ENABLE_ROCAL" OFF)
cmake_dependent_option(VISION_PACK_BUNDLE_TURBOJPEG
  "Build libjpeg-turbo from bundled source" ON
  "VISION_PACK_ENABLE_ROCAL" OFF)

# ---------------------------------------------------------------------------
# pybind11 v3.1.0  (build-time only — not shipped in final package)
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
# RapidJSON v1.1.0  (build-time only — header-only, compiled into librocal.so)
# ---------------------------------------------------------------------------
# RapidJSON is header-only — no build step needed, just expose the include path.
# We deliberately do NOT use add_subdirectory here because RapidJSON's generated
# RapidJSONConfig.cmake references parent-session targets that break sub-builds.
if(VISION_PACK_BUNDLE_RAPIDJSON)
  vision_pack_provide_header_only(RapidJSON "${CMAKE_CURRENT_SOURCE_DIR}/rapidjson")
else()
  find_package(RapidJSON REQUIRED)
endif()

# ---------------------------------------------------------------------------
# protobuf v3.21.12  (runtime dep — libprotobuf.so ships with rocAL)
# Only built when VISION_PACK_ENABLE_ROCAL=ON
# v3.22+ requires abseil-cpp as a nested submodule; v3.21.12 is the last
# release without that dependency and still satisfies rocAL's >=3.12.4 req.
# CMakeLists lives in cmake/ subdirectory for v3.21.x.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_PROTOBUF)
  set(protobuf_BUILD_TESTS          OFF CACHE BOOL "" FORCE)
  set(protobuf_BUILD_EXAMPLES       OFF CACHE BOOL "" FORCE)
  set(protobuf_WITH_ZLIB            OFF CACHE BOOL "" FORCE)
  set(protobuf_MSVC_STATIC_RUNTIME  OFF CACHE BOOL "" FORCE)
  add_subdirectory(protobuf/cmake protobuf-build)
  # protobuf v3.21.x triggers -Wstringop-overread false-positives in
  # repeated_field.h with gcc-13. GCC's toolset-13 spec in manylinux_2_28
  # promotes this to -Werror=stringop-overread, breaking the build.
  # Suppress it only on the protobuf targets.
  foreach(_pb_target libprotobuf libprotobuf-lite libprotoc protoc)
    if(TARGET ${_pb_target})
      target_compile_options(${_pb_target} PRIVATE
        -Wno-stringop-overread
        -Wno-error=stringop-overread)
    endif()
  endforeach()
  vision_pack_provide_package(protobuf Protobuf "third-party/protobuf-build")
  message(STATUS "[vision-pack] protobuf v3.21.12 bundled (ships with rocAL)")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(Protobuf REQUIRED)
endif()

# ---------------------------------------------------------------------------
# libjpeg-turbo 3.2.0  (runtime dep — libturbojpeg.so ships with rocAL)
# Only built when VISION_PACK_ENABLE_ROCAL=ON
# libjpeg-turbo explicitly forbids add_subdirectory(); must use ExternalProject.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_TURBOJPEG)
  set(_turbojpeg_install_dir "${CMAKE_BINARY_DIR}/third-party/libjpeg-turbo-install")
  ExternalProject_Add(turbojpeg_external
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/third-party/libjpeg-turbo-build"
    INSTALL_DIR "${_turbojpeg_install_dir}"
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      -DENABLE_SHARED=ON
      -DENABLE_STATIC=ON
      -DWITH_TURBOJPEG=ON
      -DWITH_SIMD=ON
    BUILD_BYPRODUCTS
      "${_turbojpeg_install_dir}/lib/libturbojpeg.so"
      "${_turbojpeg_install_dir}/lib/libjpeg.so"
  )
  set(TurboJPEG_ROOT "${_turbojpeg_install_dir}"
      CACHE PATH "Root of bundled libjpeg-turbo" FORCE)
  message(STATUS "[vision-pack] libjpeg-turbo 3.2.0 bundled via ExternalProject (ships with rocAL)")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(TurboJPEG REQUIRED)
endif()
