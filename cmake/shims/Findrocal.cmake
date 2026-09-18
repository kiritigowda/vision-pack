# Findrocal.cmake — transitional shim shipped by vision-pack.
#
# Upstream rocAL does not yet install a rocalConfig.cmake
# (https://github.com/ROCm/rocAL/issues/514), so downstream projects cannot use
# find_package(rocal CONFIG). This module lets them use find_package(rocal)
# against an installed ROCm/vision-pack tree.
#
# Remove this shim once upstream ships its own package config export.
#
# Result variables:
#   rocal_FOUND
#   rocal_INCLUDE_DIRS
#   rocal_LIBRARIES
# Imported target:
#   rocal::rocal

# <prefix>/lib/cmake/Findrocal.cmake → <prefix>
get_filename_component(_rocal_prefix "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

find_path(rocal_INCLUDE_DIR
  NAMES rocal/rocal_api.h rocal_api.h
  HINTS "${_rocal_prefix}/include" "${ROCM_PATH}/include"
  PATH_SUFFIXES rocal
)

find_library(rocal_LIBRARY
  NAMES rocal
  HINTS "${_rocal_prefix}/lib" "${ROCM_PATH}/lib"
)

set(rocal_LIBRARIES "${rocal_LIBRARY}")
set(rocal_INCLUDE_DIRS "${rocal_INCLUDE_DIR}")

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(rocal
  REQUIRED_VARS rocal_LIBRARY rocal_INCLUDE_DIR
)

if(rocal_FOUND AND NOT TARGET rocal::rocal)
  add_library(rocal::rocal UNKNOWN IMPORTED)
  set_target_properties(rocal::rocal PROPERTIES
    IMPORTED_LOCATION "${rocal_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${rocal_INCLUDE_DIR}"
  )
endif()

mark_as_advanced(rocal_INCLUDE_DIR rocal_LIBRARY)
