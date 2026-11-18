#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/bootstrap.sh
# Target ABI: arm64-v8a (default) or x86_64 (Android emulator, ChromeOS and
# other Intel/AMD devices). One APK per ABI keeps the download small.
abi="${ODLLM_ABI:-arm64-v8a}"
case "$abi" in
  arm64-v8a)
    flutter_target="android-arm64"
    build_dir="build/native-cpu-i8mm/arm64-v8a"
    fast_lib="ondevice_llm_cpu_i8mm"
    cmake_fast=("-DODLLM_LIBRARY_NAME=ondevice_llm_cpu_i8mm" "-DODLLM_ARM_ARCH=armv8.6-a+dotprod+i8mm+fp16")
    ;;
  x86_64)
    flutter_target="android-x64"
    build_dir="build/native-cpu-avx2/x86_64"
    fast_lib="ondevice_llm_cpu_avx2"
    cmake_fast=("-DODLLM_LIBRARY_NAME=ondevice_llm_cpu_avx2" "-DODLLM_X64_FAST=ON")
    ;;
  *)
    echo "ODLLM_ABI must be arm64-v8a or x86_64, got '$abi'" >&2
    exit 2
    ;;
esac
# On Linux, Vulkan builds require a host C++ compiler, Vulkan headers/library,
# and glslc. Use the Windows PowerShell script for the pinned portable toolchain.
export ORG_GRADLE_PROJECT_odllmVulkan="${ODLLM_VULKAN:-OFF}"
# OpenCL needs the Khronos link stub from scripts/bootstrap.ps1 -OpenCL (Windows path only so far).
export ORG_GRADLE_PROJECT_odllmOpenCL="${ODLLM_OPENCL:-OFF}"
# Gradle builds the portable libondevice_llm.so (baseline Armv8-A or x86-64)
# for this ABI; the fast variant built below is staged next to it in jniLibs.
export ORG_GRADLE_PROJECT_odllmAbis="$abi"
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
"$cmake_bin" -S native -B "$build_dir" -G Ninja \
  "-DCMAKE_MAKE_PROGRAM=$ninja_bin" -DCMAKE_BUILD_TYPE=Release \
  "-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake" \
  "-DANDROID_ABI=$abi" -DANDROID_PLATFORM=android-28 -DANDROID_STL=c++_static \
  -DODLLM_OPENCL=OFF -DODLLM_VULKAN=OFF -DODLLM_KLEIDIAI=OFF \
  "${cmake_fast[@]}"
"$cmake_bin" --build "$build_dir" --target "$fast_lib"
mkdir -p "android/app/src/main/jniLibs/$abi"
cp "$build_dir/lib$fast_lib.so" "android/app/src/main/jniLibs/$abi/"
dart scripts/prepare_release_registrant.dart
flutter build apk --release --target-platform "$flutter_target" --no-pub
apk="build/app/outputs/flutter-apk/app-release.apk"
unzip -Z1 "$apk" | grep -Fx "lib/$abi/lib$fast_lib.so"
unzip -Z1 "$apk" | grep -Fx "lib/$abi/libondevice_llm.so"