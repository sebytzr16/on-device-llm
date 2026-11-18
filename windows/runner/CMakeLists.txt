cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "media_import.cpp"
  "voice_audio.cpp"
  "voice_wav.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})
# Current SDK C++/WinRT headers use the standard coroutine header.
set_source_files_properties(media_import.cpp PROPERTIES COMPILE_OPTIONS "/std:c++20")

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_link_libraries(${BINARY_NAME} PRIVATE "winmm.lib")
target_link_libraries(${BINARY_NAME} PRIVATE ole32 uuid)
target_link_libraries(${BINARY_NAME} PRIVATE mfplat mfreadwrite mfuuid windowsapp)
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_executable(voice_wav_probe EXCLUDE_FROM_ALL "voice_wav.cpp" "voice_wav_probe.cpp")
apply_standard_settings(voice_wav_probe)

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# The Dart binding list is the single source of truth for the native smoke probe.
set(BRIDGE_BINDINGS "${CMAKE_CURRENT_SOURCE_DIR}/../../lib/inference/ffi/llama_bindings.dart")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${BRIDGE_BINDINGS}")
file(READ "${BRIDGE_BINDINGS}" BRIDGE_DART)
string(REGEX MATCH "kBridgeExports = \\[[^]]*\\]" BRIDGE_EXPORT_BLOCK "${BRIDGE_DART}")
string(REGEX MATCHALL "'od_[a-z_]+'" BRIDGE_EXPORTS "${BRIDGE_EXPORT_BLOCK}")
if(NOT BRIDGE_EXPORTS)
  message(FATAL_ERROR "No bridge smoke exports found")
endif()
string(REPLACE "'" "\"" BRIDGE_EXPORTS "${BRIDGE_EXPORTS}")
string(REPLACE ";" ",\n" BRIDGE_EXPORTS "${BRIDGE_EXPORTS}")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/bridge_smoke_exports.h"
  "// Generated from kBridgeExports in llama_bindings.dart.\nstatic constexpr const char* kBridgeSmokeExports[] = {\n${BRIDGE_EXPORTS}\n};\n")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
