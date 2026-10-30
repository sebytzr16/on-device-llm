# Builds the C bridge and llama.cpp as ondevice_llm.dll for Windows x64 with
# the Visual Studio Build Tools (MSVC, CMake and Ninja that ship with them)
# and stages it in native/out/windows-x64, where windows/CMakeLists.txt picks
# it up for `flutter run -d windows` and the installer.
# -Cuda builds ondevice_llm_cuda.dll (NVIDIA GPUs, needs the CUDA Toolkit) and
# stages the CUDA runtime DLLs it needs next to it; the CPU DLL stays the
# fallback when GPU acceleration is unavailable.
# -Cuda12 builds ondevice_llm_cuda12.dll against the CUDA 12.9 toolkit in
# .tools/cuda-12.9 (NVIDIA's redistributable archives, no installer) for
# drivers older than CUDA 13 needs and for Pascal/Volta GPUs CUDA 13 dropped.
# -Avx512 builds ondevice_llm_avx512.dll with a fixed x86-64-v4 baseline.
# -Compat builds ondevice_llm_compat.dll for SSE4.2 CPUs without AVX2.
# -Vulkan builds ondevice_llm_vulkan.dll using local .tools headers and the
# newest installed Android NDK glslc. MSVC generates the loader import library
# in the build directory; no Vulkan SDK or shipped driver DLL is needed.
param([switch]$Clean, [switch]$Cuda, [switch]$Cuda12, [switch]$Vulkan, [switch]$Compat, [switch]$Avx512,
      [string]$StageDir = 'native/out/windows-x64', [string]$BuildDirectory = '',
      [string]$CudaArchitectures = '')
if (([int]$Cuda.IsPresent + [int]$Cuda12.IsPresent + [int]$Vulkan.IsPresent + [int]$Compat.IsPresent + [int]$Avx512.IsPresent) -gt 1) { throw 'Build CUDA, CUDA 12, Vulkan, Compat and Avx512 in separate invocations.' }
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

# Keep builds reproducible even when bootstrap was run before a patch was added.
$llamaSource = Join-Path $projectRoot 'native/llama.cpp'
foreach ($patch in Get-ChildItem native/patches/*.patch | Sort-Object Name) {
  $ErrorActionPreference = 'Continue'
  git -c "safe.directory=$($llamaSource -replace '\\', '/')" -C $llamaSource apply --reverse --check --ignore-whitespace $patch.FullName 2>$null
  $applied = $LASTEXITCODE -eq 0
  $ErrorActionPreference = 'Stop'
  if ($applied) { continue }
  git -c "safe.directory=$($llamaSource -replace '\\', '/')" -C $llamaSource apply --ignore-whitespace $patch.FullName
  if ($LASTEXITCODE -ne 0) { throw "Patch $($patch.Name) does not apply to the pinned llama.cpp" }
}

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

$name = 'ondevice_llm'
$buildDir = 'build/native-windows/x64'
$extra = ''
$vcvarsArgs = ''
if ($Compat) {
  $name = 'ondevice_llm_compat'
  $buildDir = 'build/native-windows/x64-compat'
  $extra = "-DODLLM_X64_COMPAT=ON -DODLLM_LIBRARY_NAME=$name"
}
if ($Avx512) {
  $name = 'ondevice_llm_avx512'
  $buildDir = 'build/native-windows/x64-avx512'
  $extra = "-DODLLM_X64_AVX512=ON -DODLLM_LIBRARY_NAME=$name"
}
if ($Cuda) {
  if (-not $env:CUDA_PATH) { throw 'CUDA_PATH is not set: install the NVIDIA CUDA Toolkit.' }
  $name = 'ondevice_llm_cuda'
  $buildDir = 'build/native-windows/x64-cuda'
  # nvcc checks the MSVC version; a Build Tools release newer than the
  # toolkit is still a working host compiler.
  $extra = "-DODLLM_CUDA=ON -DODLLM_LIBRARY_NAME=$name -DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler"
}
if ($Cuda12) {
  $env:CUDA_PATH = Join-Path $projectRoot '.tools\cuda-12.9'
  $nvcc = Join-Path $env:CUDA_PATH 'bin\nvcc.exe'
  if (-not (Test-Path -LiteralPath $nvcc)) { throw 'No CUDA 12 toolkit in .tools\cuda-12.9.' }
  $name = 'ondevice_llm_cuda12'
  $buildDir = 'build/native-windows/x64-cuda12'
  $root = $env:CUDA_PATH -replace '\\', '/'
  # CUDA 12.9's front end crashes on the VS 18 (14.5x) headers; use the
  # newest VS 2022 (14.3x/14.4x) toolset the Build Tools still carry.
  $msvc = Join-Path $vcvars.Directory.Parent.Parent.Parent.FullName 'VC\Tools\MSVC'
  $toolset = Get-ChildItem -LiteralPath $msvc -Directory |
    Where-Object { $_.Name -match '^14\.[34]\d\.' } |
    Sort-Object { [version]$_.Name } -Descending |
    Select-Object -First 1
  if (-not $toolset) { throw 'CUDA 12 needs the MSVC v143 (VS 2022) toolset: add it in the Build Tools installer.' }
  $vcvarsArgs = " -vcvars_ver=$($toolset.Name)"
  $extra = "-DODLLM_CUDA=ON -DODLLM_LIBRARY_NAME=$name -DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler " +
    "-DCMAKE_CUDA_COMPILER=`"$root/bin/nvcc.exe`" -DCUDAToolkit_ROOT=`"$root`" " +
    "-DCMAKE_CUDA_ARCHITECTURES=`"61-real;70-real;75-real;80-real;86-real;89-real;89-virtual`""
}
if ($Vulkan) {
  $name = 'ondevice_llm_vulkan'
  $buildDir = 'build/native-windows/x64-vulkan'
  $ndkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk\ndk'
  $glslc = Get-ChildItem -LiteralPath $ndkRoot -Directory |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'shader-tools/windows-x86_64/glslc.exe') } |
    Sort-Object { [version]($_.Name -replace '-.*$', '') } -Descending |
    Select-Object -First 1
  if (-not $glslc) { throw 'No installed Android NDK contains Windows glslc.exe.' }
  $glslcPath = (Join-Path $glslc.FullName 'shader-tools/windows-x86_64/glslc.exe') -replace '\\', '/'
  $extra = "-DODLLM_VULKAN=ON -DODLLM_LIBRARY_NAME=$name -DVulkan_GLSLC_EXECUTABLE=`"$glslcPath`""
}
if ($BuildDirectory) { $buildDir = $BuildDirectory }
if ($CudaArchitectures) {
  if (-not ($Cuda -or $Cuda12)) { throw 'CudaArchitectures requires -Cuda or -Cuda12' }
  $extra += " -DCMAKE_CUDA_ARCHITECTURES=`"$CudaArchitectures`""
}
$outDir = $StageDir
if ($Clean -and (Test-Path -LiteralPath $buildDir)) {
  $resolvedBuild = (Resolve-Path -LiteralPath $buildDir).Path
  $buildRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'build')) + [IO.Path]::DirectorySeparatorChar
  if (-not $resolvedBuild.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Build directory is outside the workspace build root.' }
  Remove-Item -LiteralPath $resolvedBuild -Recurse -Force
}

# vcvars sets up cl.exe, the Windows SDK and their paths for this one shell.
# The commands go through a .cmd file: Windows PowerShell 5.1 mangles the
# quotes of a command line handed straight to cmd.exe.
New-Item -ItemType Directory -Force $buildDir | Out-Null
$script = Join-Path $buildDir 'build.cmd'
@(
  '@echo off',
  "call `"$($vcvars.FullName)`"$vcvarsArgs >nul || exit /b 1",
  $(if ($env:CUDA_PATH) { "set `"CUDA_PATH=$env:CUDA_PATH`"" } else { 'rem' }),
  "set `"PATH=$cmakeBin;$ninjaBin;%PATH%`"",
  "cmake -S native -B $buildDir -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl $extra || exit /b 1",
  "cmake --build $buildDir --target $name || exit /b 1"
) | Set-Content -LiteralPath $script -Encoding ascii
cmd.exe /c $script
if ($LASTEXITCODE -ne 0) { throw 'Windows native build failed' }

New-Item -ItemType Directory -Force $outDir | Out-Null
Copy-Item -LiteralPath (Join-Path $buildDir "$name.dll") -Destination $outDir -Force
if ($Cuda -or $Cuda12) {
  # The CUDA runtime and cuBLAS are redistributable (NVIDIA CUDA EULA,
  # Attachment A); the driver (nvcuda.dll) comes with the graphics driver.
  # Only bin\x64: -Include is ignored with -LiteralPath on PowerShell 5.1.
  $bin = Join-Path $env:CUDA_PATH 'bin\x64'
  if (-not (Test-Path $bin)) { $bin = Join-Path $env:CUDA_PATH 'bin' }
  $runtime = Get-ChildItem -LiteralPath $bin -File |
    Where-Object { $_.Name -match '^(cudart64|cublas64|cublasLt64)_\d+\.dll$' }
  if (-not $runtime) { throw "No CUDA runtime DLLs in $bin" }
  foreach ($dll in $runtime) { Copy-Item -LiteralPath $dll.FullName -Destination $outDir -Force }
}
Write-Output "$name.dll staged at $outDir"
