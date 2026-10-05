include(vision_pack_bundled_dep)
include(ExternalProject)
include(CMakeDependentOption)

# ---------------------------------------------------------------------------
# Install layout — mirrors TheRock / /opt/rocm exactly
#
# Vision libraries:
#   lib/lib<name>.so           shared libs
#   include/<name>/            headers
#   lib/cmake/<name>/          cmake package configs
#   share/<name>/              samples, test data
#   share/doc/<name>/          LICENSE, changelogs
#   bin/                       executables (runvx)
#
# Bundled runtime deps (turbojpeg, lmdb, libsndfile, protobuf):
#   lib/rocm_sysdeps/lib/      same prefix ROCm uses for zlib, bzip2, etc.
#
# RPATH on all vision .so files:
#   $ORIGIN/../lib/rocm_sysdeps/lib   (finds our bundled deps + existing ROCm sysdeps)
#   $ORIGIN                            (finds sibling libs: libopenvx -> libvx_rpp)
#
# ffmpeg and OpenCV are excluded — too many transitive deps.
# ---------------------------------------------------------------------------

# The rocm_sysdeps/ subdir is already the ROCm convention — no new directories.
set(VP_SYSDEPS_LIBDIR    "lib/rocm_sysdeps/lib"
    CACHE STRING "Install subdir for bundled runtime deps (matches ROCm convention)")
set(VP_SYSDEPS_INCLUDEDIR "lib/rocm_sysdeps/include"
    CACHE STRING "Install subdir for bundled runtime dep headers")

# RPATH for the bundled deps themselves. They install side by side in
# rocm_sysdeps/lib, so $ORIGIN is the only entry required. Left unset, each
# upstream build supplies its own: libjpeg-turbo an absolute stage path,
# protobuf all-empty tokens that the loader resolves against the working
# directory (#45). build_tools/rewrite_sonames.py normalizes what ships.
set(VP_BUNDLED_RPATH "$ORIGIN"
    CACHE STRING "RPATH baked into the bundled runtime deps in rocm_sysdeps/lib")

# Build-time staging prefix for bundled deps (maps to rocm_sysdeps/ at install)
set(_vp_sysdeps_stage "${CMAKE_BINARY_DIR}/third-party/rocm_sysdeps")

# ---------------------------------------------------------------------------
# Bundling options
# ---------------------------------------------------------------------------
option(VISION_PACK_BUNDLE_PYBIND11  "Build pybind11 from bundled source"        ON)
option(VISION_PACK_BUNDLE_DLPACK    "Use bundled dlpack headers"                 ON)
option(VISION_PACK_BUNDLE_RAPIDJSON "Use bundled RapidJSON headers"              ON)

# Compiled runtime deps — only when rocAL is enabled
cmake_dependent_option(VISION_PACK_BUNDLE_PROTOBUF
  "Build protobuf from bundled source"       ON "VISION_PACK_ENABLE_ROCAL" OFF)
cmake_dependent_option(VISION_PACK_BUNDLE_TURBOJPEG
  "Build libjpeg-turbo from bundled source"  ON "VISION_PACK_ENABLE_ROCAL" OFF)
cmake_dependent_option(VISION_PACK_BUNDLE_LMDB
  "Build LMDB from bundled source"           ON "VISION_PACK_ENABLE_ROCAL" OFF)
cmake_dependent_option(VISION_PACK_BUNDLE_LIBSNDFILE
  "Build libsndfile from bundled source"     ON "VISION_PACK_ENABLE_ROCAL" OFF)

# ---------------------------------------------------------------------------
# pybind11 v3.1.0  (build-time only — provides the CMake CONFIG package that
# rocAL's rocAL_pybind needs via find_package(pybind11 CONFIG)).
#
# rocAL is a separate cmake invocation (ExternalProject), so a top-level
# add_subdirectory(pybind11) is invisible to it — rocal_pybind then never builds
# ("NOTE: rocAL pybind requires pybind11, Not Found"). Install pybind11's config
# package into a dedicated build-tree stage dir and hand that to rocAL on its
# CMAKE_PREFIX_PATH (see CMakeLists.txt). rocCV is unaffected — it FetchContent's
# its own pybind11. The stage dir is NOT build/staging, so pybind11 headers never
# reach the /opt/rocm artifact; this stays build-time only.
# PYBIND11_NOPYTHON=ON lets pybind11 install its cmake tooling without resolving
# an interpreter here — Python is detected in the rocAL sub-build at consume time.
# ---------------------------------------------------------------------------
set(VP_PYBIND11_STAGE "${CMAKE_BINARY_DIR}/third-party/pybind11-stage"
    CACHE PATH "Build-tree prefix holding the bundled pybind11 CONFIG package")
if(VISION_PACK_BUNDLE_PYBIND11)
  ExternalProject_Add(pybind11_external
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/pybind11"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/third-party/pybind11-build"
    INSTALL_DIR "${VP_PYBIND11_STAGE}"
    CMAKE_ARGS
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DPYBIND11_TEST=OFF
      -DPYBIND11_INSTALL=ON
      -DPYBIND11_NOPYTHON=ON
    BUILD_BYPRODUCTS
      "${VP_PYBIND11_STAGE}/share/cmake/pybind11/pybind11Config.cmake"
  )
  message(STATUS "[vision-pack] pybind11 v3.1.0 (CONFIG package) → ${VP_PYBIND11_STAGE}")
else()
  find_package(pybind11 REQUIRED)
endif()

# ---------------------------------------------------------------------------
# dlpack v1.3  (build-time only — header-only, not installed)
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_DLPACK)
  add_subdirectory(dlpack)
  vision_pack_provide_header_only(dlpack "${CMAKE_CURRENT_SOURCE_DIR}/dlpack")
else()
  find_package(dlpack REQUIRED)
endif()

# ---------------------------------------------------------------------------
# RapidJSON master  (build-time only — compiled into librocal.so, not installed)
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_RAPIDJSON)
  vision_pack_provide_header_only(RapidJSON "${CMAKE_CURRENT_SOURCE_DIR}/rapidjson")
else()
  find_package(RapidJSON REQUIRED)
endif()

# These libraries parse untrusted JPEG, audio, LMDB, and protobuf input.
# The image compiler does not enable hardening by default, so pass it explicitly.
# _FORTIFY_SOURCE requires optimization; Release builds already supply -O2/-O3.
set(_vp_harden_flags "-fstack-protector-strong -D_FORTIFY_SOURCE=2")
string(STRIP "${CMAKE_C_FLAGS} ${_vp_harden_flags}" _vp_harden_c_flags)
string(STRIP "${CMAKE_CXX_FLAGS} ${_vp_harden_flags}" _vp_harden_cxx_flags)

# ---------------------------------------------------------------------------
# protobuf v3.21.12  → lib/rocm_sysdeps/lib/libprotobuf.so
# v3.22+ requires abseil-cpp nested submodule; v3.21.12 satisfies rocAL >=3.12.4
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_PROTOBUF)
  set(protobuf_BUILD_TESTS         OFF CACHE BOOL "" FORCE)
  set(protobuf_BUILD_EXAMPLES      OFF CACHE BOOL "" FORCE)
  set(protobuf_WITH_ZLIB           OFF CACHE BOOL "" FORCE)
  set(protobuf_MSVC_STATIC_RUNTIME OFF CACHE BOOL "" FORCE)
  # Build protobuf as a shared library so rocAL links libprotobuf.so and the
  # bundled .so we ship in rocm_sysdeps/ is the one actually used at runtime
  # (matches TheRock's sysdep model; lets protobuf be updated without relinking
  # rocAL). See issue #10.
  set(protobuf_BUILD_SHARED_LIBS   ON  CACHE BOOL "" FORCE)
  add_subdirectory(protobuf/cmake protobuf-build)
  # gcc-13 promotes -Wstringop-overread to an error in manylinux_2_28 toolset.
  # False positive in protobuf v3.21.x template copy constructors.
  foreach(_t libprotobuf libprotobuf-lite libprotoc protoc)
    if(TARGET ${_t})
      target_compile_options(${_t} PRIVATE
        -Wno-stringop-overread -Wno-error=stringop-overread
        -fstack-protector-strong)
      target_compile_definitions(${_t} PRIVATE _FORTIFY_SOURCE=2)
      # The install(CODE) glob below copies these .so's out of the build tree,
      # and file(INSTALL) performs no RPATH fixup, so the build-tree RPATH is
      # what ships. Apply the install RPATH at build time instead (#45).
      set_target_properties(${_t} PROPERTIES
        BUILD_WITH_INSTALL_RPATH ON
        INSTALL_RPATH "${VP_BUNDLED_RPATH}")
    endif()
  endforeach()
  vision_pack_provide_package(protobuf Protobuf "third-party/protobuf-build")
  # Install the shared protobuf libs into rocm_sysdeps/. protobuf writes its
  # .so's (with versioned SONAME symlinks) directly into protobuf-build/. Use a
  # glob of just the top-level .so files (not install(DIRECTORY), which would
  # recurse the whole build tree and drag in CMakeFiles/ etc.). The glob is
  # evaluated at install time via a small install(CODE) so the versioned
  # SONAMEs + symlinks that only exist after the build are all captured.
  install(CODE "
    file(GLOB _pb_sos
      \"${CMAKE_BINARY_DIR}/third-party/protobuf-build/libprotobuf.so*\"
      \"${CMAKE_BINARY_DIR}/third-party/protobuf-build/libprotobuf-lite.so*\")
    file(INSTALL \${_pb_sos}
      DESTINATION \"\${CMAKE_INSTALL_PREFIX}/${VP_SYSDEPS_LIBDIR}\")
  " COMPONENT runtime)
  message(STATUS "[vision-pack] protobuf v3.21.12 (shared) → ${VP_SYSDEPS_LIBDIR}")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(Protobuf REQUIRED)
endif()

# ---------------------------------------------------------------------------
# libjpeg-turbo 3.2.0  → lib/rocm_sysdeps/lib/libturbojpeg.so
# libjpeg-turbo forbids add_subdirectory(); use ExternalProject.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_TURBOJPEG)
  set(_tj_stage "${_vp_sysdeps_stage}")
  ExternalProject_Add(turbojpeg_external
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/third-party/libjpeg-turbo-build"
    INSTALL_DIR "${_tj_stage}"
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      # No effect today: libjpeg-turbo's CMakeLists.txt:334 sets
      # CMAKE_INSTALL_RPATH as a normal variable, which shadows this cache
      # entry and bakes in the absolute stage path. rewrite_sonames.py corrects
      # the shipped RPATH; this is kept for when upstream stops overriding it.
      "-DCMAKE_INSTALL_RPATH=${VP_BUNDLED_RPATH}"
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
      -DENABLE_SHARED=ON
      -DENABLE_STATIC=OFF
      -DWITH_TURBOJPEG=ON
      -DWITH_SIMD=ON
      "-DCMAKE_C_FLAGS:STRING=${_vp_harden_c_flags}"
      "-DCMAKE_CXX_FLAGS:STRING=${_vp_harden_cxx_flags}"
    BUILD_BYPRODUCTS
      "${_tj_stage}/lib/libturbojpeg.so"
      "${_tj_stage}/lib/libjpeg.so"
  )
  set(TurboJPEG_ROOT "${_tj_stage}" CACHE PATH "Root of bundled libjpeg-turbo" FORCE)
  # Install into rocm_sysdeps/ at package install time. Source both lib/ and
  # lib64/: CMake's GNUInstallDirs picks lib64 on manylinux_2_28 (AlmaLinux 8),
  # so the .so's land in lib64/, not lib/. Globbing both keeps this robust.
  install(DIRECTORY "${_tj_stage}/lib/" "${_tj_stage}/lib64/"
    DESTINATION "${VP_SYSDEPS_LIBDIR}"
    COMPONENT runtime
    FILES_MATCHING PATTERN "libturbojpeg.so*" PATTERN "libjpeg.so*"
  )
  message(STATUS "[vision-pack] libjpeg-turbo 3.2.0 → ${VP_SYSDEPS_LIBDIR}")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(TurboJPEG REQUIRED)
endif()

# ---------------------------------------------------------------------------
# LMDB 0.9.31  → lib/rocm_sysdeps/lib/liblmdb.so
# LMDB has no CMakeLists; built via its Makefile.
# Source lives in libraries/liblmdb/ inside the repo.
#
# Pinned to 0.9.x (Ubuntu's shipped liblmdb0 version) instead of the 1.0
# series: LMDB 1.0 changed the on-disk format (MDB_DATA_VERSION 3 vs 1) in a
# way upstream documents as permanently incompatible with 0.9 databases, and
# rocAL's Caffe/Caffe2 LMDB readers only ever consume 0.9-format DBs (#58).
#
# The 0.9.x Makefile, unlike 1.0.x, does not embed a SONAME on liblmdb.so
# (no LIBVER/ABIVER/VERSION_OPT), so rewrite_sonames.py would have nothing
# to key its isolation rename on. LDFLAGS embeds one explicitly, matching
# Ubuntu's own liblmdb.so.0.
#
# LDFLAGS also carries -pthread: the 0.9.x Makefile has no default LDFLAGS
# of its own (1.0.x's does: `LDFLAGS = $(THREADS)`), and its generic tool
# rule (`%: %.o`) links mdb_stat/mdb_copy/mdb_dump/mdb_load using only
# $(CFLAGS)/$(LDFLAGS) -- with our CFLAGS override above dropping the
# Makefile's own -pthread, those tools fail with "undefined reference to
# pthread_*" on toolchains where pthread isn't merged into libc (glibc
# < 2.34, e.g. the CI build image). liblmdb.so itself is unaffected since
# its own recipe hardcodes -pthread directly.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_LMDB)
  set(_lmdb_stage "${_vp_sysdeps_stage}")
  ExternalProject_Add(lmdb_external
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/lmdb/libraries/liblmdb"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/third-party/lmdb-build"
    INSTALL_DIR "${_lmdb_stage}"
    CONFIGURE_COMMAND ""
    BUILD_COMMAND
      make -C "${CMAKE_CURRENT_SOURCE_DIR}/lmdb/libraries/liblmdb"
        "prefix=<INSTALL_DIR>"
        "CFLAGS=-O2 -fPIC ${_vp_harden_flags}"
        "LDFLAGS=-pthread -Wl,-soname,liblmdb.so.0"
    INSTALL_COMMAND
      make -C "${CMAKE_CURRENT_SOURCE_DIR}/lmdb/libraries/liblmdb"
        "prefix=<INSTALL_DIR>"
        install
    BUILD_BYPRODUCTS "${_lmdb_stage}/lib/liblmdb.so"
  )
  set(LMDB_ROOT "${_lmdb_stage}" CACHE PATH "Root of bundled LMDB" FORCE)
  install(DIRECTORY "${_lmdb_stage}/lib/"
    DESTINATION "${VP_SYSDEPS_LIBDIR}"
    COMPONENT runtime
    FILES_MATCHING PATTERN "liblmdb.so*"
  )
  message(STATUS "[vision-pack] LMDB 0.9.31 → ${VP_SYSDEPS_LIBDIR}")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_library(LMDB_LIBRARIES NAMES lmdb)
  find_path(LMDB_INCLUDE_DIRS NAMES lmdb.h)
endif()

# ---------------------------------------------------------------------------
# libsndfile 1.2.2  → lib/rocm_sysdeps/lib/libsndfile.so
# Built without external format libs (ENABLE_EXTERNAL_LIBS=OFF) to avoid
# pulling in libvorbis, libFLAC, libopus, libmpg123 etc.
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_LIBSNDFILE)
  set(_sndfile_stage "${_vp_sysdeps_stage}")
  ExternalProject_Add(libsndfile_external
    SOURCE_DIR  "${CMAKE_CURRENT_SOURCE_DIR}/libsndfile"
    BINARY_DIR  "${CMAKE_BINARY_DIR}/third-party/libsndfile-build"
    INSTALL_DIR "${_sndfile_stage}"
    CMAKE_ARGS
      -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
      -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
      -DCMAKE_POSITION_INDEPENDENT_CODE=ON
      "-DCMAKE_INSTALL_RPATH=${VP_BUNDLED_RPATH}"
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
      -DBUILD_SHARED_LIBS=ON
      -DBUILD_PROGRAMS=OFF
      -DBUILD_EXAMPLES=OFF
      -DBUILD_TESTING=OFF
      -DENABLE_EXTERNAL_LIBS=OFF
      -DENABLE_MPEG=OFF
      # libsndfile 1.2.2 declares cmake_minimum_required(VERSION 3.1)
      # which CMake >= 3.30 rejects. Suppress the policy error.
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5
      "-DCMAKE_C_FLAGS:STRING=${_vp_harden_c_flags}"
      "-DCMAKE_CXX_FLAGS:STRING=${_vp_harden_cxx_flags}"
    BUILD_BYPRODUCTS "${_sndfile_stage}/lib/libsndfile.so"
  )
  set(SndFile_ROOT "${_sndfile_stage}" CACHE PATH "Root of bundled libsndfile" FORCE)
  # Source both lib/ and lib64/ — GNUInstallDirs installs to lib64/ on
  # manylinux_2_28 (AlmaLinux 8). See the libjpeg-turbo note above.
  install(DIRECTORY "${_sndfile_stage}/lib/" "${_sndfile_stage}/lib64/"
    DESTINATION "${VP_SYSDEPS_LIBDIR}"
    COMPONENT runtime
    FILES_MATCHING PATTERN "libsndfile.so*"
  )
  message(STATUS "[vision-pack] libsndfile 1.2.2 → ${VP_SYSDEPS_LIBDIR}")
elseif(VISION_PACK_ENABLE_ROCAL)
  find_package(SndFile QUIET)
endif()

# Expose staging prefix for top-level CMakeLists → rocAL cmake args
set(VP_BUNDLED_DEPS_STAGE "${_vp_sysdeps_stage}"
    CACHE PATH "Staging prefix for bundled runtime deps" FORCE)

# ---------------------------------------------------------------------------
# Bundled-dependency licenses. Every third-party project we build ships its
# code in an artifact, so its license must ship too. The package job checks out
# no submodules, so the license files (which live in the submodule source) are
# not available at CPack time — stage them into the artifact HERE, as part of
# the `runtime` component, then packaging/ ships each one in the package that
# carries that dep's code:
#   compiled runtime .so's (protobuf/turbojpeg/lmdb/libsndfile) → amdrocm-vision-sysdeps
#   header-only, compiled into rocAL (pybind11/dlpack/rapidjson) → amdrocm-rocal
# Each install is guarded by the same BUNDLE flag as its build above, so a
# distro build linking system copies ships no bundled license it didn't build.
set(_vp_sysdeps_licdir "share/doc/amdrocm-vision-sysdeps/licenses")
set(_vp_rocal_licdir   "share/doc/amdrocm-rocal/licenses")
if(VISION_PACK_BUNDLE_PROTOBUF)
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/protobuf/LICENSE"
    DESTINATION "${_vp_sysdeps_licdir}/protobuf" COMPONENT runtime)
endif()
if(VISION_PACK_BUNDLE_TURBOJPEG)
  # LICENSE.md defers the IJG license *text* to README.ijg, so both are needed.
  install(FILES
      "${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo/LICENSE.md"
      "${CMAKE_CURRENT_SOURCE_DIR}/libjpeg-turbo/README.ijg"
    DESTINATION "${_vp_sysdeps_licdir}/libjpeg-turbo" COMPONENT runtime)
endif()
if(VISION_PACK_BUNDLE_LMDB)
  # LICENSE is the OpenLDAP Public License; COPYRIGHT carries the notice it requires.
  install(FILES
      "${CMAKE_CURRENT_SOURCE_DIR}/lmdb/libraries/liblmdb/LICENSE"
      "${CMAKE_CURRENT_SOURCE_DIR}/lmdb/libraries/liblmdb/COPYRIGHT"
    DESTINATION "${_vp_sysdeps_licdir}/lmdb" COMPONENT runtime)
endif()
if(VISION_PACK_BUNDLE_LIBSNDFILE)
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/libsndfile/COPYING"
    DESTINATION "${_vp_sysdeps_licdir}/libsndfile" COMPONENT runtime)
endif()
if(VISION_PACK_BUNDLE_PYBIND11)
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/pybind11/LICENSE"
    DESTINATION "${_vp_rocal_licdir}/pybind11" COMPONENT runtime)
endif()
if(VISION_PACK_BUNDLE_DLPACK)
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/dlpack/LICENSE"
    DESTINATION "${_vp_rocal_licdir}/dlpack" COMPONENT runtime)
endif()
if(VISION_PACK_BUNDLE_RAPIDJSON)
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/rapidjson/license.txt"
    DESTINATION "${_vp_rocal_licdir}/rapidjson" COMPONENT runtime)
endif()
