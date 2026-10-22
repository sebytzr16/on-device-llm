param([switch]$Vulkan, [switch]$OpenCL)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
if (-not (Test-Path native/llama.cpp/include/llama.h)) {
  git clone --depth 1 --branch b11479 https://github.com/ggml-org/llama.cpp.git native/llama.cpp
  if ($LASTEXITCODE -ne 0) { throw 'llama.cpp download failed' }
}
$revision = git -C native/llama.cpp rev-parse HEAD
if ($revision -ne '42c787e8c191d49c01c757f4b7029d69ec0bf2c8') { throw 'Unexpected llama.cpp revision. Restore the pinned source.' }
if ($Vulkan) {
  New-Item -ItemType Directory -Force .tools | Out-Null
  if (-not (Test-Path .tools/llvm-mingw-20250709-ucrt-x86_64/bin/clang.exe)) {
    Invoke-WebRequest 'https://github.com/mstorsjo/llvm-mingw/releases/download/20250709/llvm-mingw-20250709-ucrt-x86_64.zip' -OutFile .tools/llvm-mingw.zip
    if ((Get-FileHash .tools/llvm-mingw.zip -Algorithm SHA256).Hash.ToLower() -ne '82babcd6aae4dc3606e8e0471d816989c384b4bf86a139f184a8b4a1b2c2758d') { throw 'Compiler archive checksum mismatch' }
    tar -xf .tools/llvm-mingw.zip -C .tools
    if ($LASTEXITCODE -ne 0) { throw 'Compiler extraction failed' }
  }
  if (-not (Test-Path .tools/Vulkan-Headers/include/vulkan/vulkan.hpp)) {
    git clone --depth 1 --branch vulkan-sdk-1.4.313.0 https://github.com/KhronosGroup/Vulkan-Headers.git .tools/Vulkan-Headers
    if ($LASTEXITCODE -ne 0) { throw 'Vulkan headers download failed' }
  }
  if ((git -C .tools/Vulkan-Headers rev-parse HEAD) -ne '409c16be502e39fe70dd6fe2d9ad4842ef2c9a53') { throw 'Unexpected Vulkan-Headers revision' }
  if (-not (Test-Path .tools/SPIRV-Headers/install/share/cmake/SPIRV-Headers/SPIRV-HeadersConfig.cmake)) {
    if (-not (Test-Path .tools/SPIRV-Headers/include/spirv/unified1/spirv.hpp)) {
      git clone --depth 1 --branch vulkan-sdk-1.4.313.0 https://github.com/KhronosGroup/SPIRV-Headers.git .tools/SPIRV-Headers
      if ($LASTEXITCODE -ne 0) { throw 'SPIRV-Headers download failed' }
    }
    if ((git -C .tools/SPIRV-Headers rev-parse HEAD) -ne 'aa6cef192b8e693916eb713e7a9ccadf06062ceb') { throw 'Unexpected SPIRV-Headers revision' }
    cmake -S .tools/SPIRV-Headers -B .tools/SPIRV-Headers/build -DCMAKE_INSTALL_PREFIX="$projectRoot/.tools/SPIRV-Headers/install" -DSPIRV_HEADERS_ENABLE_TESTS=OFF
    if ($LASTEXITCODE -ne 0) { throw 'SPIRV-Headers configure failed' }
    cmake --install .tools/SPIRV-Headers/build
    if ($LASTEXITCODE -ne 0) { throw 'SPIRV-Headers install failed' }
  }
}
if ($OpenCL) {
  # OpenCL headers plus the Khronos ICD loader, used ONLY as a link-time stub for
  # libOpenCL.so. It is never packaged: at runtime Android resolves libOpenCL.so to
  # the vendor driver declared with <uses-native-library> in the manifest.
  New-Item -ItemType Directory -Force .tools | Out-Null
  if (-not (Test-Path .tools/OpenCL-Headers/CL/cl.h)) {
    git clone --depth 1 --branch v2024.10.24 https://github.com/KhronosGroup/OpenCL-Headers.git .tools/OpenCL-Headers
    if ($LASTEXITCODE -ne 0) { throw 'OpenCL-Headers download failed' }
  }
  if ((git -C .tools/OpenCL-Headers rev-parse HEAD) -ne '4ea6df132107e3b4b9407f903204b5522fdffcd6') { throw 'Unexpected OpenCL-Headers revision' }
  if (-not (Test-Path .tools/OpenCL-ICD-Loader/build-android/libOpenCL.so)) {
    if (-not (Test-Path .tools/OpenCL-ICD-Loader/CMakeLists.txt)) {
      git clone --depth 1 --branch v2024.10.24 https://github.com/KhronosGroup/OpenCL-ICD-Loader.git .tools/OpenCL-ICD-Loader
      if ($LASTEXITCODE -ne 0) { throw 'OpenCL-ICD-Loader download failed' }
    }
    if ((git -C .tools/OpenCL-ICD-Loader rev-parse HEAD) -ne '5907ac1114079de4383cecddf1c8640e3f52f92b') { throw 'Unexpected OpenCL-ICD-Loader revision' }
    $sdkRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    $ndk = Join-Path $sdkRoot 'ndk/28.2.13676358'
    $cmake = Join-Path $sdkRoot 'cmake/3.22.1/bin/cmake.exe'
    $ninja = Join-Path $sdkRoot 'cmake/3.22.1/bin/ninja.exe'
    & $cmake -S .tools/OpenCL-ICD-Loader -B .tools/OpenCL-ICD-Loader/build-android -G Ninja "-DCMAKE_MAKE_PROGRAM=$ninja" -DCMAKE_BUILD_TYPE=Release "-DCMAKE_TOOLCHAIN_FILE=$ndk/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=28 "-DOPENCL_ICD_LOADER_HEADERS_DIR=$projectRoot/.tools/OpenCL-Headers" -DOPENCL_ICD_LOADER_BUILD_TESTING=OFF -DBUILD_TESTING=OFF
    if ($LASTEXITCODE -ne 0) { throw 'OpenCL-ICD-Loader configure failed' }
    & $cmake --build .tools/OpenCL-ICD-Loader/build-android --target OpenCL
    if ($LASTEXITCODE -ne 0) { throw 'OpenCL-ICD-Loader build failed' }
  }
}
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency resolution failed' }
Write-Output 'Dependencies ready. Generated Drift code is included. Run scripts/build-android.ps1 next.'
