param([switch]$Cuda, [string]$PrebuiltDir = '', [string]$BuildDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot
$vcvars = Get-ChildItem -LiteralPath "${env:ProgramFiles(x86)}/Microsoft Visual Studio" -Recurse -Depth 5 -Filter vcvars64.bat |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $vcvars) { throw 'Visual Studio Build Tools not found' }
$vsInstall = $vcvars.Directory.Parent.Parent.Parent.FullName
$cmakeBin = Join-Path $vsInstall 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin'
$ninjaBin = Join-Path $vsInstall 'Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja'
$variant = if ($Cuda) { 'cuda' } else { 'cpu' }
$buildDir = "build/bonsai-tests-$variant"
if ($BuildDirectory) { $buildDir = $BuildDirectory }
$extra = if ($Cuda) { '-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=86-real -DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler' } else { '-DGGML_CUDA=OFF' }
if ($PrebuiltDir) {
  $prebuilt = (Resolve-Path -LiteralPath $PrebuiltDir).Path -replace '\\', '/'
  $extra += " -DBONSAI_PREBUILT_DIR=`"$prebuilt`""
}
New-Item -ItemType Directory -Force $buildDir | Out-Null
$script = Join-Path $buildDir 'build.cmd'
@(
  '@echo off',
  "call `"$($vcvars.FullName)`" >nul || exit /b 1",
  "set `"PATH=$cmakeBin;$ninjaBin;%PATH%`"",
  "cmake -S native/tests/bonsai -B $buildDir -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl $extra || exit /b 1",
  "cmake --build $buildDir --parallel 4 --target bonsai-numerics llama-simple llama-completion llama-perplexity llama-bench llama-quantize || exit /b 1"
) | Set-Content -LiteralPath $script -Encoding ascii
cmd.exe /c $script
if ($LASTEXITCODE -ne 0) { throw 'Bonsai test build failed' }
