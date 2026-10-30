# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(ondevice_llm LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "ondevice_llm")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# The llama.cpp bridge, built separately (always optimised) by
# scripts/build-windows-native.ps1; Dart opens it as ondevice_llm.dll.
set(ODLLM_BRIDGE_DLL "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/ondevice_llm.dll")
if(NOT EXISTS "${ODLLM_BRIDGE_DLL}")
  message(FATAL_ERROR "Run scripts/build-windows-native.ps1 first to build ondevice_llm.dll")
endif()
install(FILES "${ODLLM_BRIDGE_DLL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)
# Optional CPU variants/GPU bridges and the CUDA runtime DLLs.
file(GLOB ODLLM_OPTIONAL_DLLS
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/ondevice_llm_compat.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/ondevice_llm_avx512.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/ondevice_llm_cuda.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/ondevice_llm_cuda12.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/ondevice_llm_vulkan.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/cu*.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/ggml*.dll")
if(ODLLM_OPTIONAL_DLLS)
  install(FILES ${ODLLM_OPTIONAL_DLLS} DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(DG_RUNTIME "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/diffusiongemma")
if(EXISTS "${DG_RUNTIME}/dg_host.exe")
  install(DIRECTORY "${DG_RUNTIME}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

# Image generation bridge (optional — only if built)
set(SD_DLL "${CMAKE_CURRENT_SOURCE_DIR}/../native/out/windows-x64/ondevice_sd.dll")
if(EXISTS "${SD_DLL}")
  install(FILES "${SD_DLL}" DESTINATION "${CMAKE_INSTALL_PREFIX}")
endif()

# Hash only after every DLL has been installed into the release bundle.
install(CODE "
  if(CMAKE_INSTALL_CONFIG_NAME STREQUAL \"Release\")
  execute_process(COMMAND powershell.exe -NoProfile -ExecutionPolicy Bypass
    -File \"${CMAKE_CURRENT_SOURCE_DIR}/../scripts/write-engine-manifest.ps1\"
    -Dir \"${CMAKE_INSTALL_PREFIX}\"
    RESULT_VARIABLE manifest_result)
  if(NOT manifest_result EQUAL 0)
    message(FATAL_ERROR \"Engine manifest generation failed\")
  endif()
  endif()
" COMPONENT Runtime)
