# Included by cpack once per generator, after CPackConfig.cmake and after any
# -D overrides. CPACK_GENERATOR here is the single generator being packaged.
#
# Debian and the tarball ship the pythonpath component, whose .pth lives in
# /usr/lib/python3/dist-packages. RPM ships pythonpath-rpm instead, the same
# file in /usr/lib/python3.12/site-packages, under the same package name.
# package.yml re-runs `cpack -G RPM -D CPACK_COMPONENTS_ALL=...` to stamp
# licenses on the bundling packages. Only swap when this pass was going to
# build pythonpath, so those restricted passes stay restricted.
# list(FIND) rather than IN_LIST: cpack includes this file as a script, where
# CMP0057 is not guaranteed to be NEW.
if(CPACK_GENERATOR STREQUAL "RPM")
  list(FIND CPACK_COMPONENTS_ALL pythonpath _vp_pythonpath_idx)
  if(NOT _vp_pythonpath_idx EQUAL -1)
    list(REMOVE_ITEM CPACK_COMPONENTS_ALL pythonpath)
    list(APPEND CPACK_COMPONENTS_ALL pythonpath-rpm)
  endif()
endif()
