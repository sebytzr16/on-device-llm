# Builds llama-diffusion-cli for DiffusionGemma (Gemma 4 MoE, block
# diffusion) from llama.cpp PR #24423, which is not merged yet, so it lives
# in its own checkout under build/ apart from the pinned native/llama.cpp.
# -Cuda needs the NVIDIA CUDA Toolkit. Desktop only.
# Never host-tuned (GitHub issue #4): ggml's CPU code is built for every x86
# level (GGML_CPU_ALL_VARIANTS) and ggml picks the best ggml-cpu-*.dll the CPU
# supports when dg_host starts, so AVX2-only and SSE4.2 PCs run it too.
# With GGML_BACKEND_DL the ggml target depends on every backend plugin.
param([switch]$Cuda, [string]$CudaArch = '75-real;80-real;86-real;89-real;120-real;120-virtual', [string]$Ref = 'dd7f73b19', [switch]$SkipFetch)
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

$src = Join-Path $projectRoot 'build\diffusiongemma-src'
# Git and the compilers report progress on stderr, which Windows PowerShell 5.1 turns into a
# terminating error under 'Stop'; exit codes are checked instead.
$ErrorActionPreference = 'Continue'
if (-not (Test-Path -LiteralPath (Join-Path $src '.git'))) {
  git clone --filter=blob:none https://github.com/ggml-org/llama.cpp $src 2>&1 | Out-Host
  if ($LASTEXITCODE) { throw 'clone failed' }
}
if (-not $SkipFetch) {
git -C $src fetch origin pull/24423/head 2>&1 | Out-Host
if ($LASTEXITCODE) { throw 'fetch of PR #24423 failed' }
git -C $src checkout --detach $Ref 2>&1 | Out-Host
if ($LASTEXITCODE) { throw "checkout of $Ref failed" }
}

$variant = if ($Cuda) { 'cuda' } else { 'cpu' }
$buildDir = Join-Path $src "build-$variant"
$extra = if ($Cuda) { "-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=$CudaArch" } else { '' }
$cmd = Join-Path $projectRoot "build\diffusiongemma-$variant.cmd"
@(
  "call `"$($vcvars.FullName)`" >nul || exit /b 1",
  "set `"PATH=$cmakeBin;$ninjaBin;%PATH%`"",
  "cmake -S `"$src`" -B `"$buildDir`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF -DGGML_NATIVE=OFF -DBUILD_SHARED_LIBS=ON -DGGML_BACKEND_DL=ON -DGGML_CPU_ALL_VARIANTS=ON $extra || exit /b 1",
  "cmake --build `"$buildDir`" --config Release --target llama-diffusion-cli || exit /b 1",
  "cmake -S `"$projectRoot\native\diffusiongemma`" -B `"$projectRoot\build\dg-host-$variant`" -G Ninja -DCMAKE_BUILD_TYPE=Release -DDG_SOURCE=`"$src`" -DDG_BUILD=`"$buildDir`" || exit /b 1",
  "cmake --build `"$projectRoot\build\dg-host-$variant`" || exit /b 1"
) | Set-Content -LiteralPath $cmd -Encoding ascii
cmd /c $cmd
if ($LASTEXITCODE) { throw 'build failed' }
$ErrorActionPreference = 'Stop'
Write-Host "Built $buildDir\bin\llama-diffusion-cli.exe"
$stage = Join-Path $projectRoot 'native\out\windows-x64\diffusiongemma'
# A stale host-tuned ggml-cpu.dll must not stay beside the variants.
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath "$projectRoot\build\dg-host-$variant\dg_host.exe" -Destination $stage -Force
# The CPU-variant build makes only ggml-cpu-<level>.dll; a plain ggml-cpu.dll
# in bin is left from an older host-tuned build (AVX-512, GitHub issue #4).
Remove-Item -LiteralPath "$buildDir\bin\ggml-cpu.dll" -Force -ErrorAction SilentlyContinue
Get-ChildItem -LiteralPath "$buildDir\bin" -Filter '*.dll' | Copy-Item -Destination $stage -Force
# CUDA's DLLs must live alongside the child executable too.
if ($Cuda) {
  $cudaBin = Join-Path $env:CUDA_PATH 'bin'
  Get-ChildItem -LiteralPath $cudaBin -Recurse -File |
    Where-Object { $_.Name -match '^(cudart64|cublas64|cublasLt64).*\.dll$' } |
    Copy-Item -Destination $stage -Force
}
Write-Host "Staged resident host in $stage"
