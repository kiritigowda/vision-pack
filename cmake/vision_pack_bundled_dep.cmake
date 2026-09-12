# Helpers for integrating bundled third-party dependencies.
#
# After a bundled dep is built via add_subdirectory(), call
# vision_pack_provide_package() to expose it to downstream find_package()
# calls without modifying the component submodules' CMake files.

# vision_pack_provide_package(
#   TARGET_NAME   - the CMake target produced by the bundled dep
#   PACKAGE_NAME  - the name used in downstream find_package(<PACKAGE_NAME>)
#   INSTALL_DIR   - path relative to CMAKE_BINARY_DIR where the dep installs
#                   its cmake config (e.g. "third-party/protobuf")
# )
#
# Sets <PACKAGE_NAME>_ROOT in the cache so any find_package() call issued
# after this macro resolves to the bundled copy first.
macro(vision_pack_provide_package TARGET_NAME PACKAGE_NAME INSTALL_DIR)
  set(${PACKAGE_NAME}_ROOT
      "${CMAKE_BINARY_DIR}/${INSTALL_DIR}"
      CACHE PATH
      "Root of bundled ${PACKAGE_NAME} (set by vision_pack_provide_package)"
      FORCE)
  message(STATUS
    "[vision-pack] ${PACKAGE_NAME} provided by bundled target '${TARGET_NAME}' "
    "at ${${PACKAGE_NAME}_ROOT}")
endmacro()

# vision_pack_provide_header_only(
#   PACKAGE_NAME  - the name used in downstream find_package(<PACKAGE_NAME>)
#   SOURCE_DIR    - absolute path to the submodule source tree
# )
#
# For header-only deps (rapidjson, dlpack) that need no build step — just
# point <PACKAGE_NAME>_ROOT at the source so find_package() locates the
# cmake config or include dir directly.
macro(vision_pack_provide_header_only PACKAGE_NAME SOURCE_DIR)
  set(${PACKAGE_NAME}_ROOT
      "${SOURCE_DIR}"
      CACHE PATH
      "Root of header-only bundled ${PACKAGE_NAME}"
      FORCE)
  message(STATUS
    "[vision-pack] ${PACKAGE_NAME} (header-only) provided at ${SOURCE_DIR}")
endmacro()
