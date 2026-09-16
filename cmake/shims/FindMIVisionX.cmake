# FindMIVisionX.cmake — transitional shim shipped by vision-pack.
#
# Upstream MIVisionX does not yet install a MIVisionXConfig.cmake
# (https://github.com/ROCm/MIVisionX/issues/1761), so downstream projects
# cannot use find_package(MIVisionX CONFIG). This module lets them use the
# idiomatic find_package(MIVisionX) against an installed ROCm/vision-pack tree.
#
# Remove this shim once upstream ships its own package config export.
#
# Result variables:
#   MIVisionX_FOUND
#   MIVisionX_INCLUDE_DIRS
#   MIVisionX_LIBRARIES        (libopenvx + libvxu + libvx_rpp when present)
# Imported target:
#   MIVisionX::MIVisionX

# Anchor the search at the prefix this module is installed under:
# <prefix>/lib/cmake/FindMIVisionX.cmake → <prefix>
get_filename_component(_mvx_prefix "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)

find_path(MIVisionX_INCLUDE_DIR
  NAMES mivisionx/vx_ext_rpp.h vx_ext_rpp.h
  HINTS "${_mvx_prefix}/include" "${ROCM_PATH}/include"
  PATH_SUFFIXES mivisionx
)

find_library(MIVisionX_OPENVX_LIBRARY
  NAMES openvx
  HINTS "${_mvx_prefix}/lib" "${ROCM_PATH}/lib"
)
find_library(MIVisionX_VXU_LIBRARY
  NAMES vxu
  HINTS "${_mvx_prefix}/lib" "${ROCM_PATH}/lib"
)
find_library(MIVisionX_VXRPP_LIBRARY
  NAMES vx_rpp
  HINTS "${_mvx_prefix}/lib" "${ROCM_PATH}/lib"
)

set(MIVisionX_LIBRARIES "")
foreach(_lib
    MIVisionX_OPENVX_LIBRARY MIVisionX_VXU_LIBRARY MIVisionX_VXRPP_LIBRARY)
  if(${_lib})
    list(APPEND MIVisionX_LIBRARIES "${${_lib}}")
  endif()
endforeach()
set(MIVisionX_INCLUDE_DIRS "${MIVisionX_INCLUDE_DIR}")

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(MIVisionX
  REQUIRED_VARS MIVisionX_OPENVX_LIBRARY MIVisionX_INCLUDE_DIR
)

if(MIVisionX_FOUND AND NOT TARGET MIVisionX::MIVisionX)
  add_library(MIVisionX::MIVisionX UNKNOWN IMPORTED)
  set_target_properties(MIVisionX::MIVisionX PROPERTIES
    IMPORTED_LOCATION "${MIVisionX_OPENVX_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES "${MIVisionX_INCLUDE_DIR}"
  )
endif()

mark_as_advanced(MIVisionX_INCLUDE_DIR
  MIVisionX_OPENVX_LIBRARY MIVisionX_VXU_LIBRARY MIVisionX_VXRPP_LIBRARY)
