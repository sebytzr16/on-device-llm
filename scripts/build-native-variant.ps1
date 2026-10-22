# Builds an optimized ARM bridge outside Gradle and stages it in jniLibs.
# -CpuOnly has no vendor-driver dependency; the default adds optional OpenCL.
# Gradle also builds the portable libondevice_llm.so compatibility fallback.
# Dart opens the OpenCL variant first and falls back to the CPU one when the
# device has no vendor libOpenCL.so, so one APK runs everywhere. This variant
# is also the fast CPU variant (B1): Armv8.6+dotprod+i8mm+fp16, measured +17%
# prefill on the 8 Elite, while the Gradle library stays portable Armv8-A. The
# loader checks /proc/cpuinfo before choosing it, so older arm64 CPUs never
# execute it.
param([switch]$Remove, [switch]$KleidiAI, [switch]$CpuOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$jniLibs = 'android/app/src/main/jniLibs/arm64-v8a'
$libraryName = if ($CpuOnly) { 'ondevice_llm_cpu_i8mm' } else { 'ondevice_llm_opencl' }
$output = Join-Path $jniLibs "lib$libraryName.so"
if ($Remove) {
  if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output }
  Write-Output "$libraryName variant removed."
  return
}
$sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$ndk = Join-Path $sdkRoot 'ndk/28.2.13676358'
$cmake = Join-Path $sdkRoot 'cmake/3.22.1/bin/cmake.exe'
$ninja = Join-Path $sdkRoot 'cmake/3.22.1/bin/ninja.exe'
$kleidiaiFlag = if ($KleidiAI) { 'ON' } else { 'OFF' }
$variantName = if ($KleidiAI) { 'arm64-v8a-kleidiai' } else { 'arm64-v8a' }
$backendName = if ($CpuOnly) { 'cpu-i8mm' } else { 'opencl' }
$openclFlag = if ($CpuOnly) { 'OFF' } else { 'ON' }
$buildDir = "build/native-$backendName/$variantName"
# Same toolchain settings the Gradle build uses (minSdk 28, static libc++, Release).
& $cmake -S native -B $buildDir -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninja" -DCMAKE_BUILD_TYPE=Release `
  "-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a `
  -DANDROID_PLATFORM=android-28 -DANDROID_STL=c++_static "-DODLLM_OPENCL=$openclFlag" -DODLLM_VULKAN=OFF "-DODLLM_KLEIDIAI=$kleidiaiFlag" "-DODLLM_LIBRARY_NAME=$libraryName" `
  "-DODLLM_ARM_ARCH=armv8.6-a+dotprod+i8mm+fp16"
if ($LASTEXITCODE -ne 0) { throw "$libraryName variant configure failed" }
& $cmake --build $buildDir --target $libraryName
if ($LASTEXITCODE -ne 0) { throw "$libraryName variant build failed" }
New-Item -ItemType Directory -Force $jniLibs | Out-Null
Copy-Item -LiteralPath (Join-Path $buildDir "lib$libraryName.so") -Destination $output -Force
Write-Output "$libraryName variant staged at $output"
