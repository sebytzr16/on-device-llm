# Builds the Windows chat bridge against an ik_llama.cpp checkout, for the
# optional ik_llama engine pack. It never clones or downloads anything: -Source
# is an existing checkout that must sit at the pinned commit in -Commit, and the
# build output goes to build/native-windows/ik-llama/ so the bundled llama.cpp
# bridges (and build/native-windows/x64-cuda) are never touched.
# -Avx512 builds the x86-64-v4 variant, -Compat the SSE4.2 one; the default is
# the AVX2/FMA/F16C bridge, the same three names the loader and pack expect.
# The compatibility adapters are enabled only for the ik_llama build.
param(
  [Parameter(Mandatory = $true)][string]$Source,
  [Parameter(Mandatory = $true)][string]$Commit,
  [switch]$Clean,
  [switch]$Compat,
  [switch]$Avx512,
  [string]$StageDir = 'build/native-windows/ik-llama'
)
if ([int]$Compat.IsPresent + [int]$Avx512.IsPresent -gt 1) {
  throw 'Build the Compat and Avx512 variants in separate invocations.'
}
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $projectRoot

if (-not (Test-Path -LiteralPath $Source)) { throw "ik_llama.cpp source not found: $Source" }
$ikSource = (Resolve-Path -LiteralPath $Source).Path
if (-not (Test-Path -LiteralPath (Join-Path $ikSource 'include/llama.h'))) {
  throw "$ikSource is not an ik_llama.cpp checkout (no include/llama.h)."
}
# The pack must be built from the pinned commit, or its manifest would claim a
# pin the DLLs do not come from.
$Commit = $Commit.Trim()
if ($Commit -cnotmatch '^[0-9a-f]{40}$') {
  throw 'Commit must be the full 40-character ik_llama.cpp pin.'
}
$head = & git -c "safe.directory=$($ikSource -replace '\\', '/')" -C $ikSource rev-parse HEAD 2>$null
if ($LASTEXITCODE -ne 0) { throw "$ikSource is not a git checkout; pin the source by commit first." }
if ($head.Trim() -ne $Commit) {
  throw "The checkout is at $($head.Trim()), not the pinned $Commit. Check out the pinned commit first."
}
$ikSourceCmake = $ikSource -replace '\\', '/'

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
$vsInstaller = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'

$name = 'ondevice_llm'
$variant = 'avx2'
$extra = ''
if ($Compat) {
  $name = 'ondevice_llm_compat'
  $variant = 'compat'
  $extra = '-DODLLM_X64_COMPAT=ON'
}
if ($Avx512) {
  $name = 'ondevice_llm_avx512'
  $variant = 'avx512'
  $extra = '-DODLLM_X64_AVX512=ON'
}
$buildDir = "build/native-windows/ik-build/$variant"
$outDir = $StageDir
if ($Clean) {
  # Start from a new build tree without traversing or deleting an old one.
  $buildDir += '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
}

# vcvars sets up cl.exe, the Windows SDK and their paths for this one shell.
# The commands go through a .cmd file: Windows PowerShell 5.1 mangles the
# quotes of a command line handed straight to cmd.exe.
New-Item -ItemType Directory -Force $buildDir | Out-Null
$script = Join-Path $buildDir 'build.cmd'
@(
  '@echo off',
  "set `"PATH=$vsInstaller;%PATH%`"",
  "call `"$($vcvars.FullName)`" >nul || exit /b 1",
  "set `"PATH=$cmakeBin;$ninjaBin;%PATH%`"",
  "cmake -S native -B $buildDir -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl -DODLLM_IK_LLAMA=ON -DODLLM_IK_LLAMA_SOURCE=`"$ikSourceCmake`" -DODLLM_LIBRARY_NAME=$name $extra || exit /b 1",
  "cmake --build $buildDir --target $name || exit /b 1"
) | Set-Content -LiteralPath $script -Encoding ascii
cmd.exe /c $script
if ($LASTEXITCODE -ne 0) { throw 'ik_llama.cpp bridge build failed' }

New-Item -ItemType Directory -Force $outDir | Out-Null
$outDir = (Resolve-Path -LiteralPath $outDir).Path
$stagedBridge = Join-Path $outDir "$name.dll"
$markerPath = Join-Path $outDir "$name.dll.commit.json"
# Invalidate this variant before replacing the DLL. An interrupted copy
# cannot be packaged with an older marker.
if (Test-Path -LiteralPath $markerPath) {
  Remove-Item -LiteralPath $markerPath -Force
}
$builtBridge = Join-Path $buildDir "$name.dll"
$bridgeHash = (Get-FileHash -LiteralPath $builtBridge -Algorithm SHA256).Hash.ToLowerInvariant()
Copy-Item -LiteralPath $builtBridge -Destination $stagedBridge -Force
$marker = [ordered]@{
  engine = 'ik_llama'
  commit = $head.Trim()
  sha256 = $bridgeHash
} | ConvertTo-Json
[IO.File]::WriteAllText($markerPath, $marker, (New-Object Text.UTF8Encoding($false)))
Write-Output "$name.dll ($variant) built from ik_llama.cpp $Commit and staged at $outDir"
