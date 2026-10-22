#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/bootstrap.sh
# On Linux, Vulkan builds require a host C++ compiler, Vulkan headers/library,
# and glslc. Use the Windows PowerShell script for the pinned portable toolchain.
export ORG_GRADLE_PROJECT_odllmVulkan="${ODLLM_VULKAN:-OFF}"
# OpenCL needs the Khronos link stub from scripts/bootstrap.ps1 -OpenCL (Windows path only so far).
export ORG_GRADLE_PROJECT_odllmOpenCL="${ODLLM_OPENCL:-OFF}"
# Keep optimized CPU kernels in Linux/CI releases as well as Windows builds.
sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:?Set ANDROID_HOME or ANDROID_SDK_ROOT}}"
ndk="$sdk_root/ndk/28.2.13676358"
cmake_bin="$sdk_root/cmake/3.22.1/bin/cmake"
ninja_bin="$sdk_root/cmake/3.22.1/bin/ninja"
if [[ ! -x "$cmake_bin" || ! -d "$ndk" ]]; then
  # sdkmanager is not on PATH on the GitHub runners.
  sdkmanager_bin="$sdk_root/cmdline-tools/latest/bin/sdkmanager"
  [[ -x "$sdkmanager_bin" ]] || sdkmanager_bin=sdkmanager
  "$sdkmanager_bin" "cmake;3.22.1" "ndk;28.2.13676358"
fi
"$cmake_bin" -S native -B build/native-cpu-i8mm/arm64-v8a -G Ninja \
  "-DCMAKE_MAKE_PROGRAM=$ninja_bin" -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-28 -DANDROID_STL=c++_static \
  -DODLLM_OPENCL=OFF -DODLLM_VULKAN=OFF -DODLLM_KLEIDIAI=OFF \
  -DODLLM_LIBRARY_NAME=ondevice_llm_cpu_i8mm \
  -DODLLM_ARM_ARCH=armv8.6-a+dotprod+i8mm+fp16
"$cmake_bin" --build build/native-cpu-i8mm/arm64-v8a --target ondevice_llm_cpu_i8mm
mkdir -p android/app/src/main/jniLibs/arm64-v8a
cp build/native-cpu-i8mm/arm64-v8a/libondevice_llm_cpu_i8mm.so android/app/src/main/jniLibs/arm64-v8a/
dart scripts/prepare_release_registrant.dart
flutter build apk --release --target-platform android-arm64 --no-pub
unzip -Z1 build/app/outputs/flutter-apk/app-release.apk | grep -Fx 'lib/arm64-v8a/libondevice_llm_cpu_i8mm.so'
