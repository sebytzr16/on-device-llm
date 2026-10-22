cmake_minimum_required(VERSION 3.22)
project(ondevice_llm LANGUAGES C CXX)
# The Android Gradle plugin names the CMake build type after the app variant, so a
# debug APK would carry an unoptimised llama.cpp (measured: 4 tok/s for a 135M
# model). Inference code is always built optimised; the Dart side keeps its
# debug/release split independently.
if(ANDROID)
  set(CMAKE_C_FLAGS_DEBUG "-O3 -DNDEBUG")
  set(CMAKE_CXX_FLAGS_DEBUG "-O3 -DNDEBUG")
endif()
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
# common is needed for the Jinja chat-template engine only; no HTTP/OpenSSL/subprocess.
set(LLAMA_BUILD_COMMON ON CACHE BOOL "" FORCE)
# libmtmd (vision projector for Qwen3.5 / Gemma 4 photos). Standalone target;
# video support stays off because it needs an ffmpeg subprocess.
set(LLAMA_BUILD_MTMD ON CACHE BOOL "" FORCE)
set(MTMD_VIDEO OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL OFF CACHE BOOL "" FORCE)
set(LLAMA_SUBPROCESS OFF CACHE BOOL "" FORCE)
set(LLAMA_LLGUIDANCE OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
option(ODLLM_KLEIDIAI "Build Arm KleidiAI CPU kernels (arm64 experiment)" OFF)
if(ODLLM_KLEIDIAI)
  if(NOT ANDROID OR NOT CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
    message(FATAL_ERROR "ODLLM_KLEIDIAI requires Android arm64-v8a")
  endif()
  set(GGML_CPU_KLEIDIAI ON CACHE BOOL "" FORCE)
else()
  set(GGML_CPU_KLEIDIAI OFF CACHE BOOL "" FORCE)
endif()
option(ODLLM_VULKAN "Build Vulkan backend (requires host shader toolchain)" OFF)
# The Gradle-built default library is
# the portable one: baseline Armv8-A, so it runs on every arm64 Android device
# (dot-product/fp16/i8mm kernels are compiled out; ggml falls back to NEON).
# scripts/build-native-variant.ps1 -CpuOnly builds the fast CPU variant with
# -DODLLM_ARM_ARCH=armv8.6-a+dotprod+i8mm+fp16 (SD 8 Gen 1 and newer); the
# Dart loader picks it only when every core reports i8mm in /proc/cpuinfo.
# This CPU variant does not depend on OpenCL; -OpenCL adds a third library.
set(ODLLM_ARM_ARCH "armv8-a" CACHE STRING "ARM -march for the CPU backend")
if(ANDROID AND CMAKE_ANDROID_ARCH_ABI STREQUAL "arm64-v8a")
  set(GGML_CPU_ARM_ARCH "${ODLLM_ARM_ARCH}" CACHE STRING "" FORCE)
endif()
if(ODLLM_VULKAN AND ANDROID AND CMAKE_HOST_WIN32)
  get_filename_component(ODLLM_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
  file(TO_CMAKE_PATH "${CMAKE_MAKE_PROGRAM}" ODLLM_MAKE_PROGRAM)
  configure_file("${CMAKE_CURRENT_SOURCE_DIR}/host-windows.cmake.in" "${CMAKE_BINARY_DIR}/host-windows.cmake" @ONLY)
  set(GGML_VULKAN_SHADERS_GEN_TOOLCHAIN "${CMAKE_BINARY_DIR}/host-windows.cmake" CACHE FILEPATH "" FORCE)
  set(Vulkan_GLSLC_EXECUTABLE "${ANDROID_NDK}/shader-tools/windows-x86_64/glslc.exe" CACHE FILEPATH "" FORCE)
  set(Vulkan_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.tools/Vulkan-Headers/include" CACHE PATH "" FORCE)
  set(SPIRV-Headers_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.tools/SPIRV-Headers/install/share/cmake/SPIRV-Headers" CACHE PATH "" FORCE)
  include_directories("${CMAKE_CURRENT_SOURCE_DIR}/../.tools/SPIRV-Headers/install/include")
endif()
set(GGML_VULKAN ${ODLLM_VULKAN} CACHE BOOL "" FORCE)
# OpenCL (Adreno/Mali). Links libOpenCL.so by SONAME only: the Khronos ICD loader
# under .tools is a link-time stub and is not packaged. At runtime Android resolves
# libOpenCL.so to the vendor driver declared with <uses-native-library>; on a device
# without one the app library fails to load, so this stays opt-in until GPU-01
# turns it into a separately loadable plugin.
option(ODLLM_OPENCL "Build OpenCL backend (run scripts/bootstrap.ps1 -OpenCL first)" OFF)
# GPU-01: the OpenCL build is shipped as a second library next to the CPU-only
# one (scripts/build-native-variant.ps1); Dart loads whichever the device can.
set(ODLLM_LIBRARY_NAME "ondevice_llm" CACHE STRING "Output name of the bridge library")
if(ODLLM_OPENCL AND ANDROID)
  set(OpenCL_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.tools/OpenCL-Headers" CACHE PATH "" FORCE)
  set(OpenCL_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/../.tools/OpenCL-ICD-Loader/build-android/libOpenCL.so" CACHE FILEPATH "" FORCE)
  if(NOT EXISTS "${OpenCL_LIBRARY}")
    message(FATAL_ERROR "Run scripts/bootstrap.ps1 -OpenCL to fetch the OpenCL headers and build the link stub")
  endif()
  set(GGML_OPENCL ON CACHE BOOL "" FORCE)
  set(GGML_OPENCL_EMBED_KERNELS ON CACHE BOOL "" FORCE)
  set(GGML_OPENCL_USE_ADRENO_KERNELS ON CACHE BOOL "" FORCE)
else()
  set(GGML_OPENCL OFF CACHE BOOL "" FORCE)
endif()
if(APPLE)
  set(GGML_METAL ON CACHE BOOL "" FORCE)
  set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
else()
  set(GGML_METAL OFF CACHE BOOL "" FORCE)
endif()
if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/include/llama.h")
  message(FATAL_ERROR "Run scripts/bootstrap.ps1 or scripts/bootstrap.sh first")
endif()
add_subdirectory(llama.cpp)
if(APPLE)
  add_library(${ODLLM_LIBRARY_NAME} STATIC src/bridge.cpp)
else()
  add_library(${ODLLM_LIBRARY_NAME} SHARED src/bridge.cpp)
endif()
target_include_directories(${ODLLM_LIBRARY_NAME} PRIVATE llama.cpp/include llama.cpp/ggml/include llama.cpp/vendor llama.cpp/common llama.cpp/tools/mtmd)
target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE llama-common mtmd llama)
if(ANDROID)
  target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE log)
  target_link_options(${ODLLM_LIBRARY_NAME} PRIVATE "-Wl,-z,max-page-size=16384")
endif()
