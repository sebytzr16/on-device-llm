# Builds the optional image bridge and stages it for Flutter's Windows install.
# -Cuda needs the NVIDIA CUDA Toolkit and enables the ggml CUDA backend.
# -CudaArch defaults to this PC's GPU; pass e.g. '75;86;89' for a release build.
param([switch]$Cuda, [string]$CudaArch = 'native')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

$vsRoots = @(
  "${env:ProgramFiles}\Microsoft Visual Studio",
  "${env:ProgramFiles(x86)}\Microsoft Visual Studio"
)
$vcvars = $vsRoots |
  Where-Object { Test-Path -LiteralPath $_ } |
  ForEach-Object { Get-ChildItem -LiteralPath $_ -Recurse -Depth 5 -Filter vcvars64.bat -ErrorAction SilentlyContinue } |
  Sort-Object FullName -Descending |
  Select-Object -First 1
if (-not $vcvars) { throw 'vcvars64.bat not found: install the Visual Studio Build Tools with "Desktop development with C++".' }
$vsInstall = $vcvars.Directory.Parent.Parent.Parent.FullName
$cmakeBin = Join-Path $vsInstall 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
$ninjaBin = Join-Path $vsInstall 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja'

$SD_SRC = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../native/stable-diffusion.cpp'))
$BRIDGE_SRC = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../native/src/sd_bridge.cpp'))
$OUT_DIR = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../native/out/windows-x64'))
if (-not (Test-Path -LiteralPath (Join-Path $SD_SRC 'CMakeLists.txt'))) {
  throw 'stable-diffusion.cpp is missing. Run scripts/fetch-stable-diffusion.ps1 first.'
}
if ($Cuda -and -not $env:CUDA_PATH) { throw 'CUDA_PATH is not set: install the NVIDIA CUDA Toolkit.' }
& (Join-Path $PSScriptRoot 'apply-sd-patches.ps1')

# A shallow clone does not initialize ggml. Fetch only the required submodule.
if (-not (Test-Path -LiteralPath (Join-Path $SD_SRC 'ggml/CMakeLists.txt'))) {
  # git reports progress on stderr, which Stop would turn into a failure in PS 5.1.
  $ErrorActionPreference = 'Continue'
  git -C $SD_SRC submodule update --init --depth 1 ggml 2>&1 | Out-Host
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) { throw 'stable-diffusion.cpp ggml download failed' }
}

# Kept between runs so a bridge change rebuilds in seconds, not the whole CUDA backend.
$buildDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ('../build/sd-' + $(if ($Cuda) { 'cuda' } else { 'cpu' }))))
New-Item -ItemType Directory -Force $buildDir | Out-Null
$sdPath = $SD_SRC -replace '\\', '/'
$bridgePath = $BRIDGE_SRC -replace '\\', '/'
@"
cmake_minimum_required(VERSION 3.22)
project(ondevice_sd_bridge LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(SD_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SD_BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SD_BUILD_SHARED_GGML_LIB OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(GGML_OPENBLAS OFF CACHE BOOL "" FORCE)
set(GGML_BLAS OFF CACHE BOOL "" FORCE)
set(GGML_BACKEND_DL OFF CACHE BOOL "" FORCE)
set(SD_WEBP OFF CACHE BOOL "" FORCE)
set(SD_WEBM OFF CACHE BOOL "" FORCE)
set(SD_SRC "$sdPath")
set(BRIDGE_SRC "$bridgePath")
add_subdirectory("`${SD_SRC}" sd_cpp)
# Upstream's media writer saves videos as MJPG .avi.
add_library(ondevice_sd SHARED "`${BRIDGE_SRC}"
  "`${SD_SRC}/examples/common/media_io.cpp" "`${SD_SRC}/examples/common/log.cpp"
  "`${SD_SRC}/examples/common/generation_metadata.cpp" "`${SD_SRC}/examples/common/media_metadata.cpp")
target_include_directories(ondevice_sd PRIVATE "`${SD_SRC}" "`${SD_SRC}/include" "`${SD_SRC}/examples"
  "`${SD_SRC}/src" "`${SD_SRC}/thirdparty")
target_compile_definitions(ondevice_sd PRIVATE OD_SD_MEDIA_IO)
target_link_libraries(ondevice_sd PRIVATE stable-diffusion zip)
# Keep staging independent of upstream's runtime output directory choices.
set_target_properties(ondevice_sd PROPERTIES RUNTIME_OUTPUT_DIRECTORY "`${CMAKE_BINARY_DIR}/out")
"@ | Set-Content -LiteralPath (Join-Path $buildDir 'CMakeLists.txt') -Encoding utf8

$extra = ''
if ($Cuda) { $extra = "-DGGML_CUDA=ON -DSD_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=$CudaArch" }
# Use the same vcvars/.cmd pattern as build-windows-native.ps1 for PS 5.1.
$script = Join-Path $buildDir 'build.cmd'
@(
  '@echo off',
  "call `"$($vcvars.FullName)`" >nul || exit /b 1",
  "set `"PATH=$cmakeBin;$ninjaBin;%PATH%`"",
  "cmake -S `"$buildDir`" -B `"$buildDir/build`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl $extra || exit /b 1",
  "cmake --build `"$buildDir/build`" --config Release --target ondevice_sd || exit /b 1"
) | Set-Content -LiteralPath $script -Encoding ascii
Write-Output "Building ondevice_sd.dll in $buildDir"
$ErrorActionPreference = 'Continue'
cmd.exe /c "`"$script`"" 2>&1 | Out-Host
$ErrorActionPreference = 'Stop'
if ($LASTEXITCODE -ne 0) { throw "Windows SD build failed. Build files at $buildDir" }

New-Item -ItemType Directory -Force $OUT_DIR | Out-Null
Copy-Item -LiteralPath (Join-Path $buildDir 'build/out/ondevice_sd.dll') -Destination $OUT_DIR -Force
if ($Cuda) {
  $bin = Join-Path $env:CUDA_PATH 'bin\x64'
  if (-not (Test-Path -LiteralPath $bin)) { $bin = Join-Path $env:CUDA_PATH 'bin' }
  $runtime = Get-ChildItem -LiteralPath $bin -File |
    Where-Object { $_.Name -match '^(cudart64|cublas64|cublasLt64)_\d+\.dll$' }
  if (-not $runtime) { throw "No CUDA runtime DLLs in $bin" }
  foreach ($dll in $runtime) { Copy-Item -LiteralPath $dll.FullName -Destination $OUT_DIR -Force }
}
Write-Output "Success: ondevice_sd.dll staged at $OUT_DIR"
