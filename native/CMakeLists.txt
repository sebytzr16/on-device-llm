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
# OpenMP threads on Windows: Qwen3.6 35B A3B with experts in RAM decodes at
# 31 tok/s against 17-19 with ggml's own pool (8 threads, 2026-10-29; LM
# Studio ~27). vcomp140.dll ships with the app. Android keeps ggml's pool.
if(WIN32)
  set(GGML_OPENMP ON CACHE BOOL "" FORCE)
else()
  set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
endif()
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
# Include FP8 pairs explicitly: an existing build tree can retain b11972's
# cached list, and K/V are independently selectable in the app.
set(GGML_CUDA_FA_QUANTS "f16-f16;q4_0-q4_0;q8_0-q8_0;bf16-bf16;f8_e4m3-f8_e4m3;f8_e4m3-f16;f16-f8_e4m3;f8_e4m3-q8_0;q8_0-f8_e4m3;f8_e4m3-q4_0;q4_0-f8_e4m3" CACHE STRING "App KV cache attention pairs" FORCE)
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
# Windows x64 defaults to AVX2/FMA/F16C (Haswell and Zen onwards).
# Fixed SSE4.2, AVX2 and x86-64-v4 variants; never host tuning.
option(ODLLM_X64_COMPAT "Build the Windows SSE4.2 CPU bridge" OFF)
option(ODLLM_X64_AVX512 "Build the Windows x86-64-v4 CPU bridge" OFF)
if(WIN32 AND NOT ANDROID AND CMAKE_SYSTEM_PROCESSOR MATCHES "AMD64|x86_64")
  set(GGML_SSE42 ON CACHE BOOL "" FORCE)
  if(ODLLM_X64_COMPAT)
    set(ODLLM_X64_AVX OFF)
  else()
    set(ODLLM_X64_AVX ON)
  endif()
  foreach(feature AVX AVX2 FMA F16C BMI2)
    set(GGML_${feature} ${ODLLM_X64_AVX} CACHE BOOL "" FORCE)
  endforeach()
  set(GGML_AVX512 ${ODLLM_X64_AVX512} CACHE BOOL "" FORCE)
  # These extensions are not guaranteed by PF_AVX512F or x86-64-v4.
  foreach(feature AVX_VNNI AVX512_VBMI AVX512_VNNI AVX512_BF16)
    set(GGML_${feature} OFF CACHE BOOL "" FORCE)
  endforeach()
endif()
# NVIDIA GPUs on Windows: a second bridge (ondevice_llm_cuda.dll) next to the
# CPU one; Dart opens it only where the NVIDIA driver is installed. Real
# kernels for Turing to Blackwell plus PTX so newer cards still run.
option(ODLLM_CUDA "Build the CUDA backend (Windows x64, needs the CUDA Toolkit)" OFF)
if(ODLLM_CUDA)
  if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
    set(CMAKE_CUDA_ARCHITECTURES "75-real;80-real;86-real;89-real;120-real;120-virtual")
  endif()
  set(GGML_CUDA ON CACHE BOOL "" FORCE)
else()
  set(GGML_CUDA OFF CACHE BOOL "" FORCE)
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
if(ODLLM_VULKAN AND WIN32 AND NOT ANDROID)
  set(Vulkan_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.tools/Vulkan-Headers/include" CACHE PATH "" FORCE)
  set(SPIRV-Headers_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.tools/SPIRV-Headers/install/share/cmake/SPIRV-Headers" CACHE PATH "" FORCE)
  include_directories("${CMAKE_CURRENT_SOURCE_DIR}/../.tools/SPIRV-Headers/include")
  if(NOT EXISTS "${Vulkan_GLSLC_EXECUTABLE}")
    message(FATAL_ERROR "Pass Vulkan_GLSLC_EXECUTABLE from an installed Android NDK (build-windows-native.ps1 -Vulkan)")
  endif()
  # Keep the native shader tool below MAX_PATH even in a nested worktree.
  set_property(DIRECTORY PROPERTY EP_BASE "${CMAKE_BINARY_DIR}/host")
  # The driver supplies the loader; generate only its link-time import library.
  find_program(ODLLM_DUMPBIN dumpbin REQUIRED)
  find_program(ODLLM_LIB lib REQUIRED)
  execute_process(COMMAND "${ODLLM_DUMPBIN}" /exports "$ENV{SystemRoot}/System32/vulkan-1.dll"
    OUTPUT_VARIABLE ODLLM_EXPORTS COMMAND_ERROR_IS_FATAL ANY)
  string(REGEX MATCHALL "[0-9]+[ \t]+[0-9A-Fa-f]+[ \t]+[0-9A-Fa-f]+[ \t]+vk[A-Za-z0-9_]+" ODLLM_EXPORT_LINES "${ODLLM_EXPORTS}")
  if(NOT ODLLM_EXPORT_LINES)
    message(FATAL_ERROR "No Vulkan loader exports found")
  endif()
  file(WRITE "${CMAKE_BINARY_DIR}/vulkan-1.def" "LIBRARY vulkan-1.dll\nEXPORTS\n")
  foreach(ODLLM_EXPORT IN LISTS ODLLM_EXPORT_LINES)
    string(REGEX MATCH "vk[A-Za-z0-9_]+$" ODLLM_SYMBOL "${ODLLM_EXPORT}")
    file(APPEND "${CMAKE_BINARY_DIR}/vulkan-1.def" "${ODLLM_SYMBOL}\n")
  endforeach()
  execute_process(COMMAND "${ODLLM_LIB}" "/def:${CMAKE_BINARY_DIR}/vulkan-1.def" /machine:x64
    "/out:${CMAKE_BINARY_DIR}/vulkan-1.lib" COMMAND_ERROR_IS_FATAL ANY)
  set(Vulkan_LIBRARY "${CMAKE_BINARY_DIR}/vulkan-1.lib" CACHE FILEPATH "" FORCE)
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
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp/tools/mtmd/mtmd.h" ODLLM_MTMD_H)
if(NOT ODLLM_MTMD_H MATCHES "weights_on_host")
  message(FATAL_ERROR "llama.cpp lacks native/patches: run scripts/bootstrap.ps1 or scripts/bootstrap.sh")
endif()
add_subdirectory(llama.cpp)
if(APPLE)
  add_library(${ODLLM_LIBRARY_NAME} STATIC src/bridge.cpp)
else()
  add_library(${ODLLM_LIBRARY_NAME} SHARED src/bridge.cpp)
endif()
target_include_directories(${ODLLM_LIBRARY_NAME} PRIVATE llama.cpp/include llama.cpp/ggml/include llama.cpp/vendor llama.cpp/common llama.cpp/tools/mtmd)
target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE llama-common mtmd llama)
if(WIN32)
  # GetProcessMemoryInfo (peak and current working set).
  target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE psapi)
endif()
if(ODLLM_CUDA)
  # od_gpu_device_count counts only GPUs this build has kernels for, so the
  # loader moves on (CUDA 13 -> CUDA 12) for cards outside its architectures.
  set(ODLLM_CUDA_REAL "")
  set(ODLLM_CUDA_PTX 0)
  foreach(arch IN LISTS CMAKE_CUDA_ARCHITECTURES)
    string(REGEX MATCH "^[0-9]+" cc "${arch}")
    if(arch MATCHES "-virtual$")
      set(ODLLM_CUDA_PTX ${cc})
    else()
      list(APPEND ODLLM_CUDA_REAL ${cc})
      if(NOT arch MATCHES "-real$")
        set(ODLLM_CUDA_PTX ${cc})
      endif()
    endif()
  endforeach()
  list(JOIN ODLLM_CUDA_REAL "," ODLLM_CUDA_REAL)
  find_package(CUDAToolkit REQUIRED)
  target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE CUDA::cudart)
  target_compile_definitions(${ODLLM_LIBRARY_NAME} PRIVATE
    "ODLLM_CUDA_REAL=${ODLLM_CUDA_REAL}" "ODLLM_CUDA_PTX=${ODLLM_CUDA_PTX}")
endif()
if(ANDROID)
  target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE log)
  target_link_options(${ODLLM_LIBRARY_NAME} PRIVATE "-Wl,-z,max-page-size=16384")
endif()
