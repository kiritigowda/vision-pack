cmake_minimum_required(VERSION 3.21)

project(vision-pack
  VERSION 0.2.0
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
# CMAKE_INSTALL_PREFIX defaults to ROCM_PATH. The top-level install() rules
# only cover bundled runtime deps and finder shims. Vision libraries live in
# per-project stage dirs and are copied into staging by CI before CPack —
# `cmake --install` on this project does not assemble the full /opt/rocm tree.
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
# $ORIGIN/llvm/lib                 finds libomp.so; rocAL links OpenMP, so
#   librocal.so carries a NEEDED on it and aborts at load without this (#43).
# ---------------------------------------------------------------------------
set(VP_INSTALL_RPATH
    "$ORIGIN:$ORIGIN/../lib/rocm_sysdeps/lib:$ORIGIN/llvm/lib"
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
      # USE_LINK_PATH appends absolute link-time directories that name the
      # build host's ROCM_PATH and resolve nowhere on the target.
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
  )
endif()

# roccv — no inter-library deps, only needs ROCm SDK
if(VISION_PACK_ENABLE_ROCCV)
  vision_pack_subproject_declare(roccv
    SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/roccv"
    CMAKE_ARGS
      -DBUILD_PYPACKAGE=ON
      "-DCMAKE_INSTALL_RPATH=${VP_INSTALL_RPATH}"
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
      # Forward Python3_ROOT_DIR if set (e.g. to /opt/python-shared/cp312-cp312
      # in manylinux where the static /opt/python build lacks libpython.so)
      $<$<BOOL:${Python3_ROOT_DIR}>:-DPython3_ROOT_DIR=${Python3_ROOT_DIR}>
  )
endif()

# rocPyDecode — depends only on rocDecode/rocJPEG already in the SDK.
# rocpydecode hardcodes ${ROCM_PATH}/share/rocdecode/utils for utility sources,
# which the dcgpu-tests SDK tarball provides directly under ROCM_PATH.
if(VISION_PACK_ENABLE_ROCPYDECODE)
  # Force lib/ (not lib64/). rocpydecode's videoDecode/jpegDecode use
  # GNUInstallDirs, which defaults CMAKE_INSTALL_LIBDIR to lib64 on the RHEL-
  # based manylinux image — so rocpydecode.*.so + rocpyjpegdecode.*.so land in
  # build/staging/lib64/, off the vision-pack lib/ layout (the .pth, the
  # packaging tree, and the import smoke test's PYTHONPATH all use lib/). rocCV
  # and rocAL already pin lib in their own CMakeLists; rocpydecode does not, so
  # pin it here to match — otherwise `import rocpyjpegdecode` is never found.
  set(_rocpydecode_cmake_args
    "-DROCM_PATH=${ROCM_PATH}"
    "-DCMAKE_INSTALL_LIBDIR=lib"
    # Install share/rocpydecode/tests so amdrocm-pydecode-test has a payload.
    "-DBUILD_TESTING=ON"
    # Same relative RPATH as the other vision libs (#45). USE_LINK_PATH stays
    # OFF: it appends absolute link-time directories that name the build host's
    # ROCM_PATH and resolve nowhere on the target.
    "-DCMAKE_INSTALL_RPATH=${VP_INSTALL_RPATH}"
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF)
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

  # Pin the exact Python for rocAL_pybind. Unlike rocCV/rocpydecode (which honour
  # Python3_ROOT_DIR for a single find), rocAL_pybind loops PYTHON_VERSIONS
  # 3.13..3.8 and builds a binding for EVERY interpreter it finds — so it also
  # picks up manylinux's static /opt/python/cp38 and compiles it against the
  # bundled pybind11 3.1.0, which needs Python >= 3.9 (cp38 build fails with
  # undeclared PyObject_Vectorcall / PyThreadState_GetFrame). PYTHON_VERSION_
  # SUGGESTED collapses that loop to one version. Derive major.minor from the
  # forwarded shared interpreter so it tracks Python3_ROOT_DIR, no hardcoding.
  set(_rocal_py_suggested "")
  if(Python3_ROOT_DIR AND EXISTS "${Python3_ROOT_DIR}/bin/python3")
    execute_process(
      COMMAND "${Python3_ROOT_DIR}/bin/python3" -c
              "import sys;print(f'{sys.version_info.major}.{sys.version_info.minor}')"
      OUTPUT_VARIABLE _rocal_py_suggested
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET)
  endif()

  set(_rocal_cmake_args
    -DBACKEND=HIP
    -DGPU_SUPPORT=ON
    -DBUILD_PYPACKAGE=ON
    # ffmpeg (video reader) and WebDataset (libtar) are disabled by design to
    # keep the tree self-contained. rocAL has no BUILD_WITH_* switches for these;
    # it enables each opportunistically via find_package(<Pkg> QUIET). So a stray
    # host ffmpeg/libtar-dev would silently link an untracked runtime dep (and
    # libtar flips on -DENABLE_WDS). Disable the finds so the outcome is
    # deterministic regardless of the build host (#38). OpenCV needs no flag —
    # current rocAL never looks for it.
    -DCMAKE_DISABLE_FIND_PACKAGE_FFmpeg=ON
    -DCMAKE_DISABLE_FIND_PACKAGE_LibTar=ON
    "-DCMAKE_INSTALL_RPATH=${VP_INSTALL_RPATH}"
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=OFF
    # rocAL_pybind does find_package(Python3 COMPONENTS Interpreter Development),
    # which needs libpython.so. manylinux's default static /opt/python lacks it,
    # so forward the shared Python (same as rocCV/rocpydecode) or rocal_pybind is
    # skipped even once pybind11 is found.
    $<$<BOOL:${Python3_ROOT_DIR}>:-DPython3_ROOT_DIR=${Python3_ROOT_DIR}>
    # Build ONE binding, for the forwarded interpreter, not the 3.13..3.8 sweep.
    $<$<BOOL:${_rocal_py_suggested}>:-DPYTHON_VERSION_SUGGESTED=${_rocal_py_suggested}>
  )

  if(VISION_PACK_ENABLE_MIVISIONX)
    list(APPEND _rocal_deps mivisionx)
    # rocAL's FindMIVisionX.cmake searches ${MIVisionX_PATH}/{include,lib},
    # not CMAKE_PREFIX_PATH. Point it at the mivisionx stage prefix and let
    # the finder resolve libopenvx / libvx_rpp / headers (#9).
    list(APPEND _rocal_cmake_args
      "-DMIVisionX_PATH=${CMAKE_BINARY_DIR}/_subprojects/mivisionx/stage"
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

  # rocAL_pybind's find_package(DLPACK QUIET) uses rocAL's own FindDLPACK.cmake,
  # which searches ${DLPACK_DIR}/include for dlpack/dlpack.h — it does NOT honour
  # the dlpack_ROOT that vision_pack_provide_header_only sets. Without this hint
  # DLPack is silently not found and the binding is built with ENABLE_DLPACK=0
  # (no TF/Generic-plugin GPU tensor interop). Point DLPACK_DIR at the bundled
  # header tree (header-only, compiled in — nothing installed).
  if(VISION_PACK_BUNDLE_DLPACK)
    list(APPEND _rocal_cmake_args
      "-DDLPACK_DIR=${CMAKE_CURRENT_SOURCE_DIR}/third-party/dlpack")
  endif()

  # Put the bundled sysdeps stage on rocAL's CMAKE_PREFIX_PATH so its
  # FindTurboJpeg/FindLMDB/FindSndFile modules resolve the vendored copies
  # ahead of any host devel package in /usr/lib (#38). The cache-var hints
  # (TURBO_JPEG_PATH/LMDB_DIR/SndFile_ROOT) only feed those finders' low-
  # priority PATHS slot, which loses to the system prefix; the prefix path wins.
  set(_rocal_prefix_paths "")
  if(VISION_PACK_BUNDLE_TURBOJPEG OR VISION_PACK_BUNDLE_LMDB OR VISION_PACK_BUNDLE_LIBSNDFILE)
    list(APPEND _rocal_prefix_paths "${_bstage}")
  endif()

  # rocAL_pybind does find_package(pybind11 CONFIG); the bundled pybind11 installs
  # its config package to VP_PYBIND11_STAGE (third-party/). Without this on the
  # prefix path rocal_pybind is silently skipped and `import rocal_pybind` fails.
  if(VISION_PACK_BUNDLE_PYBIND11)
    list(APPEND _rocal_extra_deps pybind11_external)
    list(APPEND _rocal_prefix_paths "${VP_PYBIND11_STAGE}")
  endif()

  vision_pack_subproject_declare(rocal
    SOURCE_DIR   "${CMAKE_CURRENT_SOURCE_DIR}/rocal"
    DEPS         ${_rocal_deps}
    EXTRA_DEPS   ${_rocal_extra_deps}
    CMAKE_ARGS   ${_rocal_cmake_args}
    PREFIX_PATHS ${_rocal_prefix_paths}
  )
endif()

# Wire up all declared subprojects
vision_pack_subproject_activate()

# Finder shims: upstream MIVisionX/rocAL ship no Config.cmake (MIVisionX#1761,
# rocAL#514). Install into staging so the dist tarball and a prefix install
# both get them; CPack also installs the same files into the -devel packages.
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/shims/FindMIVisionX.cmake"
    "${CMAKE_CURRENT_SOURCE_DIR}/cmake/shims/Findrocal.cmake"
  DESTINATION lib/cmake
  COMPONENT runtime
)
