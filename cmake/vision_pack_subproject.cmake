# vision_pack_subproject.cmake
#
# Lightweight subproject orchestration modelled on TheRock's therock_subproject.cmake.
# Each component (mivisionx, rocCV, rocal, rocpydecode) is built as an
# ExternalProject with stamp-file-based ordering so:
#   - mivisionx + rocCV build in parallel (no inter-deps)
#   - rocpydecode builds in parallel with mivisionx/rocCV (only needs SDK)
#   - third-party deps (protobuf, turbojpeg) build before rocal
#   - rocal builds last, after mivisionx stage + third-party stage
#
# Usage in top-level CMakeLists:
#
#   vision_pack_subproject_declare(mivisionx
#     SOURCE_DIR   ${CMAKE_CURRENT_SOURCE_DIR}/mivisionx
#     CMAKE_ARGS   -DROCM_PATH=${ROCM_PATH}
#   )
#   vision_pack_subproject_declare(rocal
#     SOURCE_DIR   ${CMAKE_CURRENT_SOURCE_DIR}/rocal
#     DEPS         mivisionx
#     CMAKE_ARGS   -DROCM_PATH=${ROCM_PATH}
#   )
#   vision_pack_subproject_activate()  # wire everything up

include(ExternalProject)

# ---------------------------------------------------------------------------
# Generate a FindRapidJSON.cmake shim so sub-builds can find our bundled
# header-only rapidjson via find_package(RapidJSON) without needing
# add_subdirectory (which breaks across ExternalProject boundaries).
# ---------------------------------------------------------------------------
if(VISION_PACK_BUNDLE_RAPIDJSON AND RapidJSON_ROOT)
  set(_vp_finders_dir "${CMAKE_BINARY_DIR}/vision-pack-finders")
  file(MAKE_DIRECTORY "${_vp_finders_dir}")
  file(WRITE "${_vp_finders_dir}/FindRapidJSON.cmake"
    "set(RapidJSON_INCLUDE_DIRS \"${RapidJSON_ROOT}/include\")\n"
    "set(RAPIDJSON_INCLUDE_DIRS \"${RapidJSON_ROOT}/include\")\n"
    "set(RapidJSON_FOUND TRUE)\n"
    "set(RAPIDJSON_FOUND TRUE)\n"
    "include(FindPackageHandleStandardArgs)\n"
    "find_package_handle_standard_args(RapidJSON DEFAULT_MSG RapidJSON_INCLUDE_DIRS)\n"
  )
  set(VISION_PACK_FINDERS_DIR "${_vp_finders_dir}" CACHE INTERNAL "")
endif()

# ---------------------------------------------------------------------------
# Internal state — list of declared subprojects in declaration order
# ---------------------------------------------------------------------------
set_property(GLOBAL PROPERTY _VISION_PACK_SUBPROJECTS "")

# ---------------------------------------------------------------------------
# vision_pack_subproject_declare(name
#   SOURCE_DIR <path>
#   [DEPS       <dep1> <dep2> ...]   # other subproject names this one waits for
#   [EXTRA_DEPS <target1> ...]       # raw cmake targets/stamps to wait for
#   [CMAKE_ARGS <arg> ...]           # extra -D args forwarded to cmake configure
#   [ENABLED_BY <var>]               # skip if CMake variable <var> is OFF/FALSE
# )
# ---------------------------------------------------------------------------
function(vision_pack_subproject_declare name)
  cmake_parse_arguments(PARSE_ARGV 1 ARG
    ""
    "SOURCE_DIR;ENABLED_BY"
    "DEPS;EXTRA_DEPS;CMAKE_ARGS")

  # Check optional enable guard
  if(ARG_ENABLED_BY)
    if(NOT ${ARG_ENABLED_BY})
      message(STATUS "[vision-pack] subproject '${name}' disabled (${ARG_ENABLED_BY}=OFF)")
      return()
    endif()
  endif()

  if(NOT ARG_SOURCE_DIR)
    message(FATAL_ERROR "vision_pack_subproject_declare(${name}): SOURCE_DIR is required")
  endif()

  # Per-subproject directories (mirrors TheRock's build/stage/stamp layout)
  set(_root "${CMAKE_BINARY_DIR}/_subprojects/${name}")
  set(_build_dir  "${_root}/build")
  set(_stage_dir  "${_root}/stage")
  set(_stamp_dir  "${_root}/stamp")

  # Expose dirs as global properties so activate() and dependents can find them
  set_property(GLOBAL PROPERTY _VP_${name}_SOURCE_DIR  "${ARG_SOURCE_DIR}")
  set_property(GLOBAL PROPERTY _VP_${name}_BUILD_DIR   "${_build_dir}")
  set_property(GLOBAL PROPERTY _VP_${name}_STAGE_DIR   "${_stage_dir}")
  set_property(GLOBAL PROPERTY _VP_${name}_STAMP_DIR   "${_stamp_dir}")
  set_property(GLOBAL PROPERTY _VP_${name}_DEPS        "${ARG_DEPS}")
  set_property(GLOBAL PROPERTY _VP_${name}_EXTRA_DEPS  "${ARG_EXTRA_DEPS}")
  set_property(GLOBAL PROPERTY _VP_${name}_CMAKE_ARGS  "${ARG_CMAKE_ARGS}")

  # Register in global list
  set_property(GLOBAL APPEND PROPERTY _VISION_PACK_SUBPROJECTS "${name}")
  message(STATUS "[vision-pack] declared subproject '${name}' (deps: ${ARG_DEPS})")
endfunction()

# ---------------------------------------------------------------------------
# Internal: collect CMAKE_PREFIX_PATH entries from staged deps
# ---------------------------------------------------------------------------
function(_vp_deps_to_prefix_path out_var)
  set(_paths)
  foreach(_dep ${ARGN})
    get_property(_stage_dir GLOBAL PROPERTY _VP_${_dep}_STAGE_DIR)
    if(_stage_dir)
      list(APPEND _paths "${_stage_dir}")
    endif()
  endforeach()
  set(${out_var} "${_paths}" PARENT_SCOPE)
endfunction()

# ---------------------------------------------------------------------------
# vision_pack_subproject_activate()
#
# Call once after all vision_pack_subproject_declare() calls.
# Wires up ExternalProject targets with correct stamp-file dependencies.
# ---------------------------------------------------------------------------
function(vision_pack_subproject_activate)
  get_property(_all_projects GLOBAL PROPERTY _VISION_PACK_SUBPROJECTS)

  foreach(_name ${_all_projects})
    get_property(_source_dir GLOBAL PROPERTY _VP_${_name}_SOURCE_DIR)
    get_property(_build_dir  GLOBAL PROPERTY _VP_${_name}_BUILD_DIR)
    get_property(_stage_dir  GLOBAL PROPERTY _VP_${_name}_STAGE_DIR)
    get_property(_stamp_dir  GLOBAL PROPERTY _VP_${_name}_STAMP_DIR)
    get_property(_deps       GLOBAL PROPERTY _VP_${_name}_DEPS)
    get_property(_extra_deps GLOBAL PROPERTY _VP_${_name}_EXTRA_DEPS)
    get_property(_cmake_args GLOBAL PROPERTY _VP_${_name}_CMAKE_ARGS)

    # Resolve dep ExternalProject target names (vp_<name>) for DEPENDS
    set(_ep_dep_targets)
    foreach(_dep ${_deps})
      list(APPEND _ep_dep_targets "vp_${_dep}")
    endforeach()

    # Resolve dep stage dirs → CMAKE_PREFIX_PATH for this project
    _vp_deps_to_prefix_path(_dep_prefix_paths ${_deps})

    # Build the prefix path string: dep stages + ROCM_PATH + any core overlays.
    # The core-X.Y overlay pattern is used by nightly installs where packages
    # like rpp, rocdecode, rocjpeg install into /opt/rocm/core-10.1/ rather
    # than /opt/rocm/ directly.
    set(_prefix_path_list "${_dep_prefix_paths}")
    list(APPEND _prefix_path_list "${ROCM_PATH}")
    # Add any core-X.Y overlays found under ROCM_PATH
    file(GLOB _rocm_cores "${ROCM_PATH}/core-*/lib/cmake")
    foreach(_core ${_rocm_cores})
      get_filename_component(_core_root "${_core}" DIRECTORY)
      get_filename_component(_core_root "${_core_root}" DIRECTORY)
      list(APPEND _prefix_path_list "${_core_root}" "${_core_root}/lib/llvm")
    endforeach()
    # Also honour CMAKE_PREFIX_PATH set by the parent (e.g. from CI where
    # the deb overlay is at a different path than the SDK tarball)
    if(CMAKE_PREFIX_PATH)
      list(APPEND _prefix_path_list ${CMAKE_PREFIX_PATH})
    endif()
    list(REMOVE_DUPLICATES _prefix_path_list)
    # Use | as list separator — ExternalProject LIST_SEPARATOR converts it back
    # to ; when passing -DCMAKE_PREFIX_PATH to the sub-cmake invocation.
    string(REPLACE ";" "|" _prefix_path_str "${_prefix_path_list}")

    file(MAKE_DIRECTORY "${_build_dir}" "${_stage_dir}" "${_stamp_dir}")

    # ExternalProject DEPENDS only accepts ExternalProject targets (vp_*).
    # Regular cmake targets (e.g. protobuf from add_subdirectory) must be
    # wired via add_dependencies() after ExternalProject_Add.
    ExternalProject_Add(vp_${_name}
      SOURCE_DIR        "${_source_dir}"
      BINARY_DIR        "${_build_dir}"
      INSTALL_DIR       "${_stage_dir}"
      STAMP_DIR         "${_stamp_dir}"
      # Use the same cmake binary that invoked this build — avoids picking up
      # a different cmake (e.g. pip cmake 4.x) from PATH in sub-processes.
      CMAKE_COMMAND     "${CMAKE_COMMAND}"

      # LIST_SEPARATOR tells ExternalProject to replace | back to ; in CMAKE_ARGS
      # so -DCMAKE_PREFIX_PATH=a|b|c becomes -DCMAKE_PREFIX_PATH=a;b;c correctly
      LIST_SEPARATOR    "|"

      CMAKE_ARGS
        -DCMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}
        # Stage into _stage_dir during build so dependent subprojects can
        # find headers/libs before the final install to ROCM_PATH.
        # Each library's own CMakeLists defaults CMAKE_INSTALL_PREFIX to
        # ROCM_PATH — we override to the stage dir here.
        -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
        -DROCM_PATH=${ROCM_PATH}
        "-DCMAKE_PREFIX_PATH=${_prefix_path_str}"
        # Inject our generated finders (FindRapidJSON.cmake etc.) into sub-builds
        "-DCMAKE_MODULE_PATH=${VISION_PACK_FINDERS_DIR}"
        ${_cmake_args}

      BUILD_COMMAND
        ${CMAKE_COMMAND} --build <BINARY_DIR> --parallel ${VP_BUILD_PARALLEL_LEVEL}

      # Stage install: installs to _stage_dir (build-time use by dependents)
      INSTALL_COMMAND
        ${CMAKE_COMMAND} --install <BINARY_DIR> --prefix <INSTALL_DIR>
        COMMAND ${CMAKE_COMMAND} -E touch "${_stamp_dir}/stage.stamp"

      # Only ExternalProject targets here
      DEPENDS           ${_ep_dep_targets}

      CMAKE_CACHE_ARGS
        # Force amdclang — subprojects need ROCm's clang, not the system gcc
        # that the top-level project was configured with.
        "-DCMAKE_C_COMPILER:STRING=${ROCM_PATH}/lib/llvm/bin/amdclang"
        "-DCMAKE_CXX_COMPILER:STRING=${ROCM_PATH}/lib/llvm/bin/amdclang++"
        # Forward Python3_ROOT_DIR if set at the top level (e.g. to
        # /opt/python-shared/cp312-cp312 in manylinux where the default
        # /opt/python build lacks libpython.so needed for Development.Embed).
        $<$<BOOL:${Python3_ROOT_DIR}>:-DPython3_ROOT_DIR:PATH=${Python3_ROOT_DIR}>
    )

    # Wire regular cmake targets (add_subdirectory) as dependencies separately
    if(_extra_deps)
      add_dependencies(vp_${_name} ${_extra_deps})
    endif()

    # Plain alias without vp_ prefix for readability
    add_custom_target(${_name} DEPENDS vp_${_name})

    message(STATUS "[vision-pack] activated subproject '${_name}'"
      " stage=${_stage_dir}"
      " deps=[${_deps}]")
  endforeach()
endfunction()
