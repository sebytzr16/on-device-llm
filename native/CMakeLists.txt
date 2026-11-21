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
# Android x86_64 splits the same way as arm64: the Gradle build is the portable
# one (baseline x86-64, because ggml turns every instruction set off when
# cross-compiling), and scripts/build_android.sh stages a second library with
# Haswell kernels. Dart loads it only when every core reports avx2 in
# /proc/cpuinfo, so an Atom without AVX2 keeps the portable library.
option(ODLLM_X64_FAST "Build the Android x86_64 AVX2 CPU bridge" OFF)
if(ODLLM_X64_FAST)
  if(NOT ANDROID OR NOT CMAKE_ANDROID_ARCH_ABI STREQUAL "x86_64")
    message(FATAL_ERROR "ODLLM_X64_FAST requires Android x86_64")
  endif()
  set(GGML_SSE42 ON CACHE BOOL "" FORCE)
  foreach(feature AVX AVX2 FMA F16C BMI2)
    set(GGML_${feature} ON CACHE BOOL "" FORCE)
  endforeach()
  set(GGML_AVX512 OFF CACHE BOOL "" FORCE)
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
# The optional ik_llama.cpp engine builds the same bridge against another
# llama.cpp fork (scripts/build-ik-llama.ps1). Its source tree is passed in and
# never replaces native/llama.cpp, so the bundled engine cannot change.
option(ODLLM_IK_LLAMA "Build the chat bridge against an ik_llama.cpp checkout" OFF)
set(ODLLM_IK_LLAMA_SOURCE "" CACHE PATH "Existing ik_llama.cpp checkout, pinned by scripts/build-ik-llama.ps1")
# A normal variable, never cached: a build tree can never keep pointing at a
# fork after a later bundled configure.
set(ODLLM_LLAMA_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/llama.cpp")
if(ODLLM_IK_LLAMA)
  if(NOT WIN32 OR ANDROID)
    message(FATAL_ERROR "ODLLM_IK_LLAMA is a Windows x64 engine only")
  endif()
  if(NOT ODLLM_IK_LLAMA_SOURCE OR NOT EXISTS "${ODLLM_IK_LLAMA_SOURCE}/include/llama.h")
    message(FATAL_ERROR "Pass -DODLLM_IK_LLAMA_SOURCE=<ik_llama.cpp checkout> (scripts/build-ik-llama.ps1 -Source)")
  endif()
  set(ODLLM_LLAMA_SOURCE "${ODLLM_IK_LLAMA_SOURCE}")
  if(ODLLM_X64_COMPAT)
    set(GGML_IQK_MUL_MAT OFF CACHE BOOL "" FORCE)
  endif()
endif()
if(NOT EXISTS "${ODLLM_LLAMA_SOURCE}/include/llama.h")
  if(ODLLM_IK_LLAMA)
    message(FATAL_ERROR "The ik_llama.cpp checkout has no include/llama.h")
  endif()
  message(FATAL_ERROR "Run scripts/bootstrap.ps1 or scripts/bootstrap.sh first")
endif()
# The app's llama.cpp carries local patches (mtmd, fit, MTP). They belong to the
# bundled engine only: an ik_llama.cpp checkout is built as it is, and its
# differences are handled by native/src/ik_compat.inc.
if(NOT ODLLM_IK_LLAMA)
  file(READ "${ODLLM_LLAMA_SOURCE}/tools/mtmd/mtmd.h" ODLLM_MTMD_H)
  if(NOT ODLLM_MTMD_H MATCHES "weights_on_host")
    message(FATAL_ERROR "llama.cpp lacks native/patches: run scripts/bootstrap.ps1 or scripts/bootstrap.sh")
  endif()
endif()
if(ODLLM_IK_LLAMA)
  # The fork's top-level build generates common/build-info.cpp in its source
  # checkout. Configure the library subdirectories and generate that file here.
  set(CMAKE_CXX_STANDARD 20)
  set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
  set(GGML_LLAMAFILE ON)
  if(MSVC)
    add_compile_definitions(_CRT_SECURE_NO_WARNINGS)
    add_compile_options(/utf-8 /bigobj)
  endif()
  find_package(Threads REQUIRED)
  find_package(Git REQUIRED)
  set(ik_git "${GIT_EXECUTABLE}" -c "safe.directory=${ODLLM_LLAMA_SOURCE}" -C "${ODLLM_LLAMA_SOURCE}")
  execute_process(COMMAND ${ik_git} rev-parse --short HEAD OUTPUT_VARIABLE BUILD_COMMIT
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  execute_process(COMMAND ${ik_git} rev-list --count HEAD OUTPUT_VARIABLE BUILD_NUMBER
    OUTPUT_STRIP_TRAILING_WHITESPACE COMMAND_ERROR_IS_FATAL ANY)
  set(BUILD_COMPILER "${CMAKE_C_COMPILER_ID} ${CMAKE_C_COMPILER_VERSION}")
  set(BUILD_TARGET "${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR}")
  configure_file("${ODLLM_LLAMA_SOURCE}/common/build-info.cpp.in" "ik-build-info.cpp" @ONLY)
  add_subdirectory("${ODLLM_LLAMA_SOURCE}/ggml" llama.cpp/ggml)
  add_subdirectory("${ODLLM_LLAMA_SOURCE}/src" llama.cpp/src)
  # Use the pinned fork's common target source list, with absolute paths back
  # to the checkout. The list is parsed, not included: the fork's file resolves
  # its relative paths against CMAKE_CURRENT_SOURCE_DIR and generates
  # common/build-info.cpp inside the checkout, so including it would write into
  # the read-only source tree (this project generates ik-build-info.cpp
  # instead). Optional curl and llguidance dependencies remain off.
  file(STRINGS "${ODLLM_LLAMA_SOURCE}/common/CMakeLists.txt" ik_common_lines)
  set(ik_common_sources "")
  set(ik_read_common OFF)
  foreach(line IN LISTS ik_common_lines)
    string(STRIP "${line}" line)
    if(line MATCHES "^add_library\\([^ )]+ STATIC")
      set(ik_read_common ON)
    elseif(ik_read_common AND line STREQUAL ")")
      break()
    elseif(ik_read_common AND NOT line STREQUAL "reasoning-budget.cpp")
      # sampling.cpp already includes reasoning-budget.cpp at this pin.
      list(APPEND ik_common_sources "${ODLLM_LLAMA_SOURCE}/common/${line}")
    endif()
  endforeach()
  if(NOT ik_common_sources)
    message(FATAL_ERROR "Cannot locate the ik_llama common target source list")
  endif()
  # The parse is pinned to ik_llama.cpp 464613d7: a pin bump that reformats or
  # extends the list must say so here, not fail later as a missing symbol.
  set(ik_common_expected 53)
  list(LENGTH ik_common_sources ik_common_count)
  if(NOT ik_common_count EQUAL ik_common_expected)
    message(FATAL_ERROR "The common target of ${ODLLM_LLAMA_SOURCE} lists ${ik_common_count} sources, "
      "expected ${ik_common_expected} for pin 464613d7: update native/CMakeLists.txt for the new pin")
  endif()
  add_library(common STATIC ${ik_common_sources} "${CMAKE_CURRENT_BINARY_DIR}/ik-build-info.cpp")
  target_include_directories(common PUBLIC "${ODLLM_LLAMA_SOURCE}/common" "${ODLLM_LLAMA_SOURCE}/vendor")
  target_link_libraries(common PUBLIC llama Threads::Threads)
else()
  add_subdirectory(${ODLLM_LLAMA_SOURCE} llama.cpp)
endif()
if(APPLE)
  add_library(${ODLLM_LIBRARY_NAME} STATIC src/bridge.cpp)
else()
  add_library(${ODLLM_LIBRARY_NAME} SHARED src/bridge.cpp)
endif()
target_include_directories(${ODLLM_LIBRARY_NAME} PRIVATE
  ${ODLLM_LLAMA_SOURCE}/include ${ODLLM_LLAMA_SOURCE}/ggml/include
  ${ODLLM_LLAMA_SOURCE}/vendor ${ODLLM_LLAMA_SOURCE}/common)
# The common helpers are `llama-common` in the bundled pin; older forks still
# call the target `common`.
if(TARGET llama-common)
  target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE llama-common)
elseif(TARGET common)
  target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE common)
else()
  message(FATAL_ERROR "The engine source has no llama-common/common target")
endif()
target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE llama)
# libmtmd is the vision projector: the bundled llama.cpp has it, an ik_llama.cpp
# checkout may not, and its descriptor declares vision unsupported.
if(ODLLM_IK_LLAMA)
  if(NOT TARGET mtmd)
    add_subdirectory("${ODLLM_LLAMA_SOURCE}/examples/mtmd" ik-mtmd EXCLUDE_FROM_ALL)
  endif()
  target_include_directories(${ODLLM_LIBRARY_NAME} PRIVATE ${ODLLM_LLAMA_SOURCE}/examples/mtmd)
  target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE mtmd)
elseif(TARGET mtmd)
  target_include_directories(${ODLLM_LIBRARY_NAME} PRIVATE ${ODLLM_LLAMA_SOURCE}/tools/mtmd)
  target_link_libraries(${ODLLM_LIBRARY_NAME} PRIVATE mtmd)
else()
  target_compile_definitions(${ODLLM_LIBRARY_NAME} PRIVATE OD_IK_NO_MTMD)
endif()
if(ODLLM_IK_LLAMA)
  # bridge.cpp includes native/src/ik_compat.inc under this define only.
  target_compile_definitions(${ODLLM_LIBRARY_NAME} PRIVATE OD_IK_LLAMA)
endif()
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
